import AppKit
import Carbon.HIToolbox

/// Keyboard control:
/// - hold ⌃ Control + ⌥ Option to talk, and let go to finish;
/// - press Space while holding them for hands-free recording that carries on after you let go;
///   press ⌃⌥ again (or ⌃⌥ Space) to finish;
/// - Esc cancels.
/// Holding the pair and pressing another key, or clicking, is treated as an ordinary shortcut:
/// nothing starts, and a recording that had just started is dropped.
/// Watching ⌃⌥ needs Accessibility; ⌃⌥ Space is a registered hot key and works without it.
@MainActor
final class DictationKeys {
    enum Intent: String {
        case startTalking, stopTalking, abandonTalking, handsFree, escape
    }

    /// Called when ⌃⌥ go down. Return true if the press was used (to finish hands-free
    /// recording), so that this hold does not start talking.
    var onChordDown: () -> Bool = { false }
    var onIntent: (Intent) -> Void = { _ in }

    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            space.register(isEnabled ? GlobalShortcut.controlOptionSpace : nil)
            if !isEnabled { reset() }
        }
    }

    /// Grace period before talking starts, so ⌃⌥ shortcuts in other apps do not record.
    private static let startDelay: TimeInterval = 0.15
    private static let chord: NSEvent.ModifierFlags = [.control, .option]
    private static let tracked: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]

    private let space = GlobalShortcut()
    private var monitors: [Any] = []
    private var chordHeld = false
    /// Another key or a click happened during this hold, or the hold was already used.
    private var chordSpoiled = false
    /// A hold-to-talk recording is running from this hold.
    private var talking = false
    private var pendingStart: DispatchWorkItem?

    func start() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
        space.onPress = { [weak self] in self?.spacePressed() }
        if isEnabled { space.register(GlobalShortcut.controlOptionSpace) }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let flags = event.modifierFlags.intersection(Self.tracked)
            if flags == Self.chord {
                guard !chordHeld else { return }
                chordHeld = true
                chordSpoiled = false
                talking = false
                guard isEnabled else { return }
                if onChordDown() {
                    chordSpoiled = true
                } else {
                    scheduleStart()
                }
            } else if chordHeld {
                chordHeld = false
                cancelPendingStart()
                if talking {
                    talking = false
                    onIntent(.stopTalking)
                }
            }
        case .keyDown:
            if event.keyCode == UInt16(kVK_Escape) { onIntent(.escape) }
            // Space while holding ⌃⌥ belongs to the hot key (spacePressed), not to this check.
            guard chordHeld, event.keyCode != UInt16(kVK_Space) else { return }
            spoil()
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if chordHeld { spoil() }
        default:
            break
        }
    }

    private func spoil() {
        chordSpoiled = true
        cancelPendingStart()
        if talking {
            talking = false
            onIntent(.abandonTalking)
        }
    }

    private func scheduleStart() {
        cancelPendingStart()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.chordHeld, !self.chordSpoiled, self.pendingStart != nil else { return }
                self.pendingStart = nil
                self.talking = true
                self.onIntent(.startTalking)
            }
        }
        pendingStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.startDelay, execute: work)
    }

    private func cancelPendingStart() {
        pendingStart?.cancel()
        pendingStart = nil
    }

    /// ⌃⌥ Space. A registered hot key, so the space is not typed into the focused app.
    private func spacePressed() {
        cancelPendingStart()
        chordSpoiled = true  // this hold now belongs to hands-free
        talking = false      // so letting go of ⌃⌥ must not stop the recording
        onIntent(.handsFree)
    }

    private func reset() {
        cancelPendingStart()
        chordHeld = false
        chordSpoiled = false
        talking = false
    }
}
