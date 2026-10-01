import AppKit
import ApplicationServices

/// After Humm pastes a transcript, reads the text field it went into for up to two minutes and
/// reports words the user corrects (see Corrections). Reads through Accessibility on a
/// background queue, only the text around the paste unless the app offers nothing narrower, and
/// never logs or keeps what it reads.
@MainActor
final class CorrectionWatcher {
    /// Called on the main thread with corrections not reported before.
    var onCorrections: ([Corrections.Candidate]) -> Void = { _ in }
    /// Whether a word is ordinary English, so that changing to it is a grammar fix, not a term.
    var isKnownWord: (String) -> Bool = { word in
        let checker = NSSpellChecker.shared
        return !checker.hasLearnedWord(word) && checker.checkSpelling(of: word, startingAt: 0).location == NSNotFound
    }
    var isEnabled = true {
        didSet { if !isEnabled { cancel() } }
    }

    private static let pollInterval: TimeInterval = 0.25
    /// Unchanged for this long after an edit, the edit counts as done, unless the caret is still
    /// in the edited words (the user may be mid-word).
    private static let settleTime: TimeInterval = 2
    /// Unchanged for this long, it counts as done wherever the caret is: after retyping a short
    /// paste the caret always sits next to the word.
    private static let restTime: TimeInterval = 5
    private static let watchTime: TimeInterval = 120

    private final class Session {
        let id: Int
        let field: TextField
        let anchor: Anchor
        let started = Date()
        var text: String
        var changed = Date()
        var settled = true
        var rested = true
        /// From the latest reading in which the pasted text could still be found.
        var latest = Corrections.Result(found: true, candidates: [])
        var caret: Int?
        var reported: Set<String> = []
        var failures = 0

        init(id: Int, field: TextField, anchor: Anchor, snapshot: Snapshot) {
            self.id = id
            self.field = field
            self.anchor = anchor
            text = snapshot.text
            caret = snapshot.caret
        }
    }

    private let queue = DispatchQueue(label: "com.kyser.humm.corrections")
    private var session: Session?
    /// Bumped whenever watching starts or stops, so late results from an old watch are dropped.
    private var generation = 0

    /// Watches the focused field for corrections to `pasted`, which Humm has just pasted.
    func watch(pasted: String) {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        begin(pasted: pasted) { TextField.focused(inApp: pid) }
    }

    /// Self-test: watches a given text element instead of the focused one.
    func watch(pasted: String, in element: AXUIElement, readsRanges: Bool) {
        let field = TextField(element: element, pid: 0, app: "self-test", readsRanges: readsRanges)
        begin(pasted: pasted) { field }
    }

    /// Stops watching, first reporting corrections seen so far, even where the caret still is.
    func finish() {
        generation += 1
        guard let session else { return }
        self.session = nil
        report(session, final: true)
    }

    /// Stops watching without reporting anything.
    func cancel() {
        generation += 1
        session = nil
    }

    private func begin(pasted: String, field: @escaping @Sendable () -> TextField?) {
        finish()
        guard isEnabled, !pasted.isEmpty else { return }
        let id = generation
        queue.async { [weak self] in
            let located = TextField.locate(pasted, in: field)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == id else { return }
                    switch located {
                    case let .found(field, anchor, snapshot):
                        self.session = Session(id: id, field: field, anchor: anchor, snapshot: snapshot)
                        Log.app.notice("learn: watching \(field.app, privacy: .public) \(field.role, privacy: .public), reading \(field.readsRanges ? "around the paste" : "the whole field", privacy: .public)")
                        self.schedulePoll(id)
                    case let .missing(reason):
                        Log.app.notice("learn: not watching: \(reason, privacy: .public)")
                    }
                }
            }
        }
    }

    private func schedulePoll(_ id: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in
            MainActor.assumeIsolated { self?.poll(id) }
        }
    }

    private func poll(_ id: Int) {
        guard let session, session.id == id else { return }
        guard Date().timeIntervalSince(session.started) < Self.watchTime else { return finish() }
        let field = session.field
        let anchor = session.anchor
        queue.async { [weak self] in
            let snapshot = field.snapshot(of: anchor)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.received(snapshot, for: id) }
            }
        }
    }

    private func received(_ snapshot: Snapshot?, for id: Int) {
        guard let session, session.id == id else { return }
        defer { if self.session === session { schedulePoll(id) } }
        guard let snapshot else {
            session.failures += 1
            if session.failures >= 3 {
                Log.app.notice("learn: field no longer readable")
                finish()
            }
            return
        }
        session.failures = 0
        session.caret = snapshot.caret
        guard snapshot.text != session.text else {
            let quiet = Date().timeIntervalSince(session.changed)
            if !session.settled, quiet >= Self.settleTime {
                session.settled = true
                report(session, final: false)
            }
            if !session.rested, quiet >= Self.restTime {
                session.rested = true
                report(session, final: true)
            }
            return
        }
        session.text = snapshot.text
        session.changed = Date()
        session.settled = false
        session.rested = false
        let result = Corrections.find(pasted: session.anchor.pasted, before: session.anchor.before,
                                      after: session.anchor.after, edited: snapshot.text, isKnownWord: isKnownWord)
        guard result.found else {
            Log.app.notice("learn: pasted text gone (\(result.kept, privacy: .public) of \(result.pasted, privacy: .public) words left, field \(snapshot.text.isEmpty ? "empty" : "not empty", privacy: .public))")
            return finish()
        }
        session.latest = result
    }

    /// `final`: report corrections even where the caret still is.
    private func report(_ session: Session, final: Bool) {
        let fresh = session.latest.candidates.filter { candidate in
            guard !session.reported.contains(Self.key(candidate)) else { return false }
            // The caret in or next to the edited words: the user may still be typing them.
            if !final, let caret = session.caret,
               caret >= candidate.range.location, caret <= NSMaxRange(candidate.range) { return false }
            return true
        }
        guard !fresh.isEmpty else { return }
        fresh.forEach { session.reported.insert(Self.key($0)) }
        Log.app.notice("learn: \(fresh.count, privacy: .public) correction(s)")
        onCorrections(fresh)
    }

    private static func key(_ candidate: Corrections.Candidate) -> String {
        candidate.from + "\u{1F}" + candidate.to
    }
}

/// Where the pasted text sat when it was pasted. Offsets are UTF-16, as Accessibility counts.
private struct Anchor: Sendable {
    let pasted: String
    let start: Int
    let length: Int
    /// Length of the whole field then.
    let fieldLength: Int
    let before: String
    let after: String
}

private struct Snapshot: Sendable {
    /// The stretch of the field around the pasted text.
    let text: String
    /// Caret position in `text`, if the app reports one.
    let caret: Int?
}

/// A text field in another app, read through Accessibility. Used only on the watcher's queue.
private final class TextField: @unchecked Sendable {
    enum Located: Sendable {
        case found(TextField, Anchor, Snapshot)
        case missing(String)
    }

    /// Characters read either side of the paste, to find it again after edits.
    private static let context = 120
    /// Most new text read beyond the paste, in characters.
    private static let maxGrowth = 4_000
    /// A field that can't hand out part of its text is read whole, only up to this length.
    private static let wholeTextLimit = 20_000
    /// Pauses before looking for the pasted text: apps take a moment to handle ⌘V.
    private static let locateDelays: [TimeInterval] = [0.15, 0.3, 0.5, 0.8]
    /// Apps already asked to switch on their accessibility tree.
    private nonisolated(unsafe) static var askedApps: Set<pid_t> = []

    let element: AXUIElement
    let pid: pid_t
    /// Bundle identifier of the app, for the log.
    let app: String
    private(set) var role = ""
    /// Whether the app hands out parts of its text ("string for range"). If not, the whole text
    /// is read, and only for short fields.
    private(set) var readsRanges: Bool

    init(element: AXUIElement, pid: pid_t, app: String, readsRanges: Bool) {
        self.element = element
        self.pid = pid
        self.app = app
        self.readsRanges = readsRanges
    }

    static func focused(inApp app: pid_t) -> TextField? {
        guard let element = AX.focusedElement(of: app) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != getpid() else { return nil }
        let app = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)"
        return TextField(element: element, pid: pid, app: app, readsRanges: true)
    }

    /// Waits for the paste to land, then finds it in the field.
    static func locate(_ pasted: String, in find: () -> TextField?) -> Located {
        var reason = "no focused element"
        for delay in locateDelays {
            Thread.sleep(forTimeInterval: delay)
            guard let field = find() else { continue }
            field.role = AX.string(field.element, kAXRoleAttribute) ?? "no role"
            if AX.string(field.element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
                return .missing("secure text field")
            }
            if let anchor = field.anchor(for: pasted), let snapshot = field.snapshot(of: anchor) {
                return .found(field, anchor, snapshot)
            }
            reason = "pasted text not found in \(field.app) \(field.role)"
            field.askForAccessibilityOnce()
        }
        return .missing(reason)
    }

    /// Electron apps (Slack, VS Code, many chat apps) build their accessibility tree only when
    /// asked. Other apps ignore the request.
    private func askForAccessibilityOnce() {
        guard pid > 0, !Self.askedApps.contains(pid) else { return }
        Self.askedApps.insert(pid)
        let result = AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if result == .success { Log.app.notice("learn: asked \(self.app, privacy: .public) for its accessibility tree") }
    }

    private var value: String? { AX.string(element, kAXValueAttribute) }
    private var length: Int? { AX.int(element, kAXNumberOfCharactersAttribute) ?? value.map { ($0 as NSString).length } }
    private var caret: Int? { AX.range(element, kAXSelectedTextRangeAttribute).map { $0.location + $0.length } }

    /// Finds `pasted` just before the caret, where a paste leaves it, or for a short field read
    /// whole, its last occurrence.
    private func anchor(for pasted: String) -> Anchor? {
        let count = (pasted as NSString).length
        guard let total = length, total >= count else { return nil }
        let caret = caret
        if readsRanges, let caret, caret >= count, let text = text(in: NSRange(location: caret - count, length: count)) {
            return Self.same(text, pasted) ? anchor(pasted, at: caret - count, total: total) : nil
        }
        readsRanges = false
        guard total <= Self.wholeTextLimit, let value else { return nil }
        let all = value as NSString
        if let caret, caret >= count, caret <= all.length,
           Self.same(all.substring(with: NSRange(location: caret - count, length: count)), pasted) {
            return anchor(pasted, at: caret - count, total: total)
        }
        let found = all.range(of: pasted, options: .backwards)
        return found.location == NSNotFound ? nil : anchor(pasted, at: found.location, total: total)
    }

    private func anchor(_ pasted: String, at start: Int, total: Int) -> Anchor? {
        let count = (pasted as NSString).length
        let end = start + count
        guard let before = text(in: NSRange(location: max(0, start - Self.context), length: min(Self.context, start))),
              let after = text(in: NSRange(location: end, length: max(0, min(Self.context, total - end))))
        else { return nil }
        return Anchor(pasted: pasted, start: start, length: count, fieldLength: total, before: before, after: after)
    }

    /// The stretch of the field around the pasted text now: the context either side, widened by
    /// however much the field has grown or shrunk.
    func snapshot(of anchor: Anchor) -> Snapshot? {
        guard let total = length else { return nil }
        let grown = min(max(0, total - anchor.fieldLength), Self.maxGrowth)
        let shrunk = max(0, anchor.fieldLength - total)
        let lower = max(0, anchor.start - Self.context - shrunk)
        let upper = min(total, anchor.start + anchor.length + grown + Self.context)
        guard upper > lower else { return Snapshot(text: "", caret: nil) }
        guard let text = text(in: NSRange(location: lower, length: upper - lower)) else { return nil }
        return Snapshot(text: text, caret: caret.map { $0 - lower })
    }

    private func text(in range: NSRange) -> String? {
        guard range.length > 0 else { return "" }
        if readsRanges { return AX.string(element, in: range) }
        guard let value else { return nil }
        let all = value as NSString
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: all.length))
        return clamped.length > 0 ? all.substring(with: clamped) : ""
    }

    /// Equal apart from spacing and curly quotes, which some apps change on paste.
    private static func same(_ a: String, _ b: String) -> Bool {
        normalised(a) == normalised(b)
    }

    private static func normalised(_ text: String) -> String {
        text.replacingOccurrences(of: "[‘’]", with: "'", options: .regularExpression)
            .replacingOccurrences(of: "[“”]", with: "\"", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Typed reads of Accessibility attributes.
enum AX {
    /// Electron apps (Slack, VS Code, many chat apps) build their accessibility tree only when an
    /// assistive app asks. Asking the app being dictated into when recording starts means its text
    /// field can be found by the time the transcript is ready. Once per app; others ignore it.
    @MainActor
    static func askForTree(pid: pid_t, name: String) {
        guard pid > 0, pid != getpid(), !askedApps.contains(pid) else { return }
        askedApps.insert(pid)
        let result = AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if result == .success { Log.app.notice("asked \(name, privacy: .public) for its accessibility tree") }
    }

    @MainActor private static var askedApps: Set<pid_t> = []

    /// The focused element of an app, falling back to the system-wide query.
    static func focusedElement(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)  // a busy app must not hold us up for long
        if let element = element(app, kAXFocusedUIElementAttribute) { return element }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.5)
        return element(system, kAXFocusedUIElementAttribute)
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (copy(element, attribute) as? [AnyObject] ?? []).compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func int(_ element: AXUIElement, _ attribute: String) -> Int? {
        (copy(element, attribute) as? NSNumber)?.intValue
    }

    static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    static func string(_ element: AXUIElement, in range: NSRange) -> String? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var value: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                                parameter, &value)
        return status == .success ? value as? String : nil
    }
}
