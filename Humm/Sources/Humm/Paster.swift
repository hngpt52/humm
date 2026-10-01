import AppKit
import ApplicationServices

/// Inserts text into the focused app by pasting, then restores the user's clipboard.
enum Paster {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @MainActor
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let changeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // Give the target app time to read the pasteboard before restoring it. Skip the
        // restore if something else wrote to the clipboard in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard pasteboard.changeCount == changeCount else { return }
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
        }
    }
}

/// The element with keyboard focus, as Accessibility reports it: whether a paste would land
/// somewhere. Reads roles only, never text.
struct Focus {
    enum Target {
        /// Something that takes text: paste there.
        case text
        /// The app reports focus on something else (a page, a button, a list), or has no window:
        /// nowhere to paste, so Humm offers the transcript to copy.
        case other
        /// The app reports no focused element but has a window, e.g. an Electron app whose
        /// accessibility tree is still being built. Humm pastes, as it always has.
        case unknown
    }

    @MainActor
    static func pasteTarget(in app: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) -> Target {
        if let focus = current(in: app) { return focus.takesText ? .text : .other }
        guard let app, app.processIdentifier != getpid() else { return .unknown }
        return AX.element(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute) == nil ? .other : .unknown
    }

    let role: String
    let subrole: String?
    /// Bundle identifier of the app it belongs to.
    let app: String
    let pid: pid_t
    /// A text field or area (including editable web content), a combo box or a search field.
    let takesText: Bool

    /// Asks the app itself: with Chrome in front, the system-wide focus query fails (cannot
    /// complete) while the app answers at once.
    @MainActor
    static func current(in app: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) -> Focus? {
        guard let app, app.processIdentifier != getpid(), let element = AX.focusedElement(of: app.processIdentifier) else { return nil }
        let role = AX.string(element, kAXRoleAttribute) ?? ""
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        // Other roles that edit text say so: their value can be set and they have a caret.
        var settable: DarwinBoolean = false
        let editable = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue && AX.range(element, kAXSelectedTextRangeAttribute) != nil
        return Focus(role: role, subrole: AX.string(element, kAXSubroleAttribute),
                     app: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)", pid: pid,
                     takesText: [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) || editable)
    }
}
