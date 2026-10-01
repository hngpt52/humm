import AppKit
import Carbon.HIToolbox

/// A system-wide key combination (a Carbon hot key) that reports press and release.
/// Unlike an event monitor it needs no Accessibility permission, and the keystroke is
/// consumed instead of being typed into the focused app.
@MainActor
final class GlobalShortcut {
    struct Combo: Equatable {
        /// Stable name for saving the choice.
        let id: String
        let keyCode: UInt32
        /// Carbon modifier mask.
        let modifiers: UInt32
        /// How the shortcut is written in the menu and captions.
        let label: String
    }

    /// Hands-free dictation. (⌥ Opt + Space would clash with the ChatGPT app's launcher: when two
    /// apps register the same combo only one of them receives it.)
    static let controlOptionSpace = Combo(id: "control-option-space", keyCode: UInt32(kVK_Space),
                                          modifiers: UInt32(controlKey | optionKey), label: "⌃ Ctrl + ⌥ Opt + Space")

    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    private(set) var combo: Combo?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// Holding the keys can repeat the press; only the first counts until the release.
    private var isDown = false

    init() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { pressed ? shortcut.pressed() : shortcut.released() }
            return noErr
        }, types.count, &types, context, &handler)
    }

    private func pressed() {
        guard !isDown else { return }
        isDown = true
        onPress()
    }

    private func released() {
        isDown = false
        onRelease()
    }

    /// Registers `combo`, or turns the shortcut off for nil. Returns false if another app holds it.
    @discardableResult
    func register(_ combo: Combo?) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        self.combo = nil
        guard let combo else { return true }
        let id = EventHotKeyID(signature: OSType(0x484D_4D31), id: 1)  // "HMM1"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKey = ref
        self.combo = combo
        return true
    }
}
