import AppKit
import AVFoundation

@MainActor
final class AppState {
    enum Phase: Equatable {
        case idle, recording, transcribing
        /// Brief confirmation after a successful paste.
        case done
        /// Information, e.g. the transcript was copied rather than pasted.
        case notice(String)
        case error(String)
        /// Words were added to the dictionary.
        case learned(String)
        /// A transcript from history was copied.
        case copied

        var name: String {
            switch self {
            case .idle: "idle"
            case .recording: "recording"
            case .transcribing: "transcribing"
            case .done: "done"
            case .notice: "notice"
            case .error: "error"
            case .learned: "learned"
            case .copied: "copied"
            }
        }
    }

    /// Recordings shorter than this are treated as accidental and discarded.
    private static let minimumDuration: TimeInterval = 0.3
    /// Recordings whose loudest moment is quieter than this (dBFS) are silence and not sent:
    /// the models answer silence with invented text.
    private static let silenceLevel: Float = -55

    /// Called after any change the UI shows.
    var onChange: () -> Void = {}

    private(set) var phase: Phase = .idle {
        didSet {
            guard phase != oldValue else { return }
            Log.app.notice("phase -> \(self.phase.name, privacy: .public)")
            scheduleReturnToIdle()
            onChange()
        }
    }
    private(set) var lastTranscript = ""
    /// Stop to text pasted, in milliseconds.
    private(set) var lastLatencyMs: Int?
    /// What the last transcription cost, in US dollars.
    private(set) var lastCost: Double?

    var model: TranscriptionModel {
        didSet {
            UserDefaults.standard.set(model.rawValue, forKey: "model")
            onChange()
        }
    }
    var showFloatingButton: Bool {
        didSet {
            UserDefaults.standard.set(showFloatingButton, forKey: "showFloatingButton")
            onChange()
        }
    }
    /// With more than one display, the pill moves to the one the pointer is on (see FloatingPill).
    var pillFollowsMouse: Bool {
        didSet {
            UserDefaults.standard.set(pillFollowsMouse, forKey: "pillFollowsMouse")
            onChange()
        }
    }
    var playSounds: Bool {
        didSet {
            UserDefaults.standard.set(playSounds, forKey: "playSounds")
            onChange()
        }
    }

    /// Current microphone loudness (0...1) while recording, for the level meter.
    var inputLevel: Float {
        guard phase == .recording else { return 0 }
        if previewing { return Float(0.45 + 0.35 * sin(Date().timeIntervalSinceReferenceDate * 7)) }
        return recorder.level()
    }

    /// Set by `--preview`: shows a state without recording, for checking how the pill looks.
    private var previewing = false

    /// Hold ⌃⌥ to talk, ⌃⌥ Space for hands-free (see DictationKeys).
    var keyboardShortcuts: Bool {
        didSet {
            UserDefaults.standard.set(keyboardShortcuts, forKey: "keyboardShortcuts")
            keys.isEnabled = keyboardShortcuts
            onChange()
        }
    }

    /// Learn words from corrections to pasted text (see CorrectionWatcher).
    var learnFromCorrections: Bool {
        didSet {
            UserDefaults.standard.set(learnFromCorrections, forKey: "learnFromCorrections")
            corrections.isEnabled = learnFromCorrections
            onChange()
        }
    }

    let dictionary = UserDictionary()
    let history: TranscriptHistory
    let costs: CostTracker
    let insights: Insights

    /// Turn American spellings into British ones (see BritishSpelling). On by default where British
    /// spelling is the norm.
    var britishSpelling: Bool {
        didSet {
            UserDefaults.standard.set(britishSpelling, forKey: "britishSpelling")
            onChange()
        }
    }

    /// Write spoken paths, flags and sizes as they are typed (see TechnicalText).
    var technicalFormatting: Bool {
        didSet {
            UserDefaults.standard.set(technicalFormatting, forKey: "technicalFormatting")
            onChange()
        }
    }

    private static var britishRegion: Bool {
        ["GB", "IE", "AU", "NZ", "ZA"].contains(Locale.current.region?.identifier ?? "")
    }
    let snippets: SnippetStore

    /// Keep transcripts in the history (see TranscriptHistory).
    var keepHistory: Bool {
        didSet {
            UserDefaults.standard.set(keepHistory, forKey: "keepHistory")
            onChange()
        }
    }

    /// A transcript with nowhere to paste (no text box selected), shown in a card by the pill
    /// with a Copy button until it is copied, closed or replaced.
    private(set) var transcriptToCopy: String?
    private(set) var transcriptCopied = false
    /// Bumped each time the card changes, so its timers only close the card they were set for.
    private var cardGeneration = 0

    /// Words just learned, shown in a card with Undo. `before` is the dictionary to go back to.
    struct LearnedNotice {
        let words: [String]
        let detail: String
        let before: [UserDictionary.Word]
    }

    private(set) var learnedNotice: LearnedNotice?

    /// A recording that could not be transcribed, kept so nothing is lost: Try Again sends it
    /// again; closing the card (or quitting) deletes it.
    struct FailedRecording {
        let url: URL
        let duration: TimeInterval
        let reason: String
    }

    private(set) var failedRecording: FailedRecording?
    private var noticeGeneration = 0

    enum RecordingMode { case holdToTalk, handsFree }

    /// Recording that carries on until finished (click, ⌃⌥ or ⌃⌥ Space), as opposed to
    /// hold-to-talk, which finishes when the keys are let go.
    var isHandsFree: Bool { phase == .recording && mode == .handsFree }

    private let recorder = Recorder()
    private let keys = DictationKeys()
    private let corrections = CorrectionWatcher()
    private var mode = RecordingMode.handsFree

    init() {
        let defaults = UserDefaults.standard
        model = defaults.string(forKey: "model").flatMap(TranscriptionModel.init(rawValue:)) ?? .gpt4oMiniTranscribe
        showFloatingButton = defaults.object(forKey: "showFloatingButton") as? Bool ?? true
        pillFollowsMouse = defaults.object(forKey: "pillFollowsMouse") as? Bool ?? true
        playSounds = defaults.object(forKey: "playSounds") as? Bool ?? true
        keyboardShortcuts = defaults.object(forKey: "keyboardShortcuts") as? Bool ?? true
        keepHistory = defaults.object(forKey: "keepHistory") as? Bool ?? true
        britishSpelling = defaults.object(forKey: "britishSpelling") as? Bool ?? Self.britishRegion
        technicalFormatting = defaults.object(forKey: "technicalFormatting") as? Bool ?? true
        // `--history-file <path>` (developer previews) reads and writes another file.
        let arguments = CommandLine.arguments
        history = arguments.firstIndex(of: "--history-file").flatMap { index in
            index + 1 < arguments.count ? TranscriptHistory(file: URL(fileURLWithPath: arguments[index + 1])) : nil
        } ?? TranscriptHistory()
        // `--snippets-file <path>` likewise.
        snippets = arguments.firstIndex(of: "--snippets-file").flatMap { index in
            index + 1 < arguments.count ? SnippetStore(file: URL(fileURLWithPath: arguments[index + 1])) : nil
        } ?? SnippetStore()
        // `--costs-file <path>` likewise.
        costs = arguments.firstIndex(of: "--costs-file").flatMap { index in
            index + 1 < arguments.count ? CostTracker(file: URL(fileURLWithPath: arguments[index + 1])) : nil
        } ?? CostTracker()
        // `--insights-file <path>` likewise.
        insights = arguments.firstIndex(of: "--insights-file").flatMap { index in
            index + 1 < arguments.count ? Insights(file: URL(fileURLWithPath: arguments[index + 1])) : nil
        } ?? Insights()
        learnFromCorrections = defaults.object(forKey: "learnFromCorrections") as? Bool ?? true
        corrections.isEnabled = learnFromCorrections
        corrections.onCorrections = { [weak self] found in self?.learn(found) }
        keys.onChordDown = { [weak self] in self?.chordPressed() ?? false }
        keys.onIntent = { [weak self] intent in self?.handle(intent) }
        keys.isEnabled = keyboardShortcuts
        keys.start()
        // A new insights file starts from what History kept; never from previews or sample history.
        if insights.isNew, !arguments.contains(where: { $0.hasPrefix("--preview") || $0 == "--history-file" }) {
            insights.seed(from: history.entries)
        }
    }

    var statusText: String {
        switch phase {
        case .idle:
            APIKeyStore.locate() == nil
                ? "No API key: choose Add API Key… in the menu."
                : keyboardShortcuts ? "Ready. Hold ⌃ Ctrl + ⌥ Opt to dictate, or click the pill." : "Ready. Click the pill to dictate."
        case .recording:
            mode == .handsFree
                ? "Listening, hands-free. Press ⌃ Ctrl + ⌥ Opt or click the pill to finish."
                : "Listening. Let go of ⌃ Ctrl + ⌥ Opt to finish."
        case .transcribing: "Transcribing…"
        case .done: "Pasted."
        case let .notice(message), let .error(message): message
        case let .learned(words): "Learned: \(words)"
        case .copied: "Copied."
        }
    }

    var menuBarSymbol: String {
        switch phase {
        case .idle: "waveform"
        case .recording: "mic.fill"
        case .transcribing: "ellipsis.circle"
        case .done: "checkmark.circle"
        case .notice: "doc.on.clipboard"
        case .error: "exclamationmark.triangle"
        case .learned: "character.book.closed"
        case .copied: "doc.on.clipboard"
        }
    }

    /// Developer preview: `Humm --preview recording|transcribing|done|notice|error`.
    func preview(_ name: String) {
        previewing = true
        switch name {
        case "recording": phase = .recording
        case "transcribing": phase = .transcribing
        case "done": phase = .done
        case "notice": phase = .notice("Copied: press ⌘V. Allow Accessibility to auto-paste.")
        case "error": phase = .error("OpenAI 401: Incorrect API key provided.")
        case "learned":
            phase = .learned("Plannr")
            showLearned(LearnedNotice(words: ["Plannr"], detail: "Fix \u{201C}planner\u{201D} once more and Humm will change it by itself.",
                                      before: dictionary.words))
        case "card": offerTranscript("Push the Plannr fix to Supabase before the launch, then tell the team it is live.")
        case "failed":
            failedRecording = FailedRecording(url: FileManager.default.temporaryDirectory.appendingPathComponent("humm-preview.m4a"),
                                              duration: 69.7, reason: "OpenAI didn't reply in time.")
            phase = .error("OpenAI didn't reply in time.")
        default: break
        }
    }

    /// Click: start listening (hands-free), or finish and transcribe.
    func toggle() {
        switch phase {
        case .recording: finishRecording()
        case .transcribing: break
        case .idle, .done, .notice, .error, .learned, .copied: startRecording(mode: .handsFree)
        }
    }

    // MARK: Keyboard

    /// ⌃⌥ went down. While recording hands-free, that finishes the recording.
    private func chordPressed() -> Bool {
        guard phase == .recording, mode == .handsFree else { return false }
        Log.input.notice("keys: finish hands-free")
        finishRecording()
        return true
    }

    private func handle(_ intent: DictationKeys.Intent) {
        Log.input.notice("keys: \(intent.rawValue, privacy: .public)")
        switch intent {
        case .startTalking:
            switch phase {
            case .idle, .done, .notice, .error, .learned, .copied: startRecording(mode: .holdToTalk)
            case .recording, .transcribing: break
            }
        case .stopTalking:
            if phase == .recording, mode == .holdToTalk { finishRecording() }
        case .abandonTalking:
            if phase == .recording, mode == .holdToTalk { cancelRecording() }
        case .handsFree:
            switch phase {
            case .recording where mode == .holdToTalk:
                mode = .handsFree  // keep going after the keys are let go
                onChange()
            case .recording:
                finishRecording()
            case .transcribing:
                break
            case .idle, .done, .notice, .error, .learned, .copied:
                startRecording(mode: .handsFree)
            }
        case .escape:
            if phase == .recording { cancelRecording() } else if transcriptToCopy != nil { closeTranscript() } else { closeLearned() }
        }
    }

    // MARK: Nowhere to paste

    /// Shows the transcript in a card with a Copy button instead of pasting.
    private func offerTranscript(_ text: String) {
        cardGeneration += 1
        transcriptToCopy = text
        transcriptCopied = false
        onChange()
        let card = cardGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, self.cardGeneration == card else { return }
            self.closeTranscript()
        }
    }

    func copyTranscript() {
        guard let text = transcriptToCopy, !transcriptCopied else { return }
        Paster.copy(text)
        Log.input.notice("card: copied")
        cardGeneration += 1
        transcriptCopied = true
        onChange()
        let card = cardGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, self.cardGeneration == card else { return }
            self.closeTranscript()
        }
    }

    func closeTranscript() {
        guard transcriptToCopy != nil else { return }
        cardGeneration += 1
        transcriptToCopy = nil
        transcriptCopied = false
        onChange()
    }

    // MARK: History

    private func record(_ text: String, _ outcome: Transcript.Outcome, seconds: TimeInterval, model: TranscriptionModel, cost: Double) {
        guard keepHistory else { return }
        history.add(Transcript(text: text, app: NSWorkspace.shared.frontmostApplication?.localizedName,
                               outcome: outcome, seconds: seconds, model: model.rawValue, cost: cost))
    }

    func copyFromHistory(_ transcript: Transcript) {
        Paster.copy(transcript.text)
        Log.input.notice("history: copied")
        switch phase {
        case .recording, .transcribing: break
        default: phase = .copied
        }
    }

    func clearHistory() {
        history.clear()
        Log.input.notice("history: cleared")
        onChange()
    }

    // MARK: Dictionary

    func removeWord(_ text: String) {
        dictionary.remove(text)
        onChange()
    }

    private func learn(_ found: [Corrections.Candidate]) {
        let before = dictionary.words
        let words = dictionary.learn(found)
        insights.recordLearned(words.count)
        Log.app.notice("dictionary: \(words.count, privacy: .public) word(s) learned")
        onChange()
        guard let first = words.first else { return }
        switch phase {
        case .idle, .done, .notice, .error, .learned, .copied:
            phase = .learned(words.joined(separator: ", "))
            showLearned(LearnedNotice(words: words, detail: learnedDetail(for: first, before: before), before: before))
        case .recording, .transcribing:
            break
        }
    }

    /// What Humm will now do with the word: replace a spelling, wait for one more fix, or hint.
    private func learnedDetail(for word: String, before: [UserDictionary.Word]) -> String {
        guard let now = dictionary.words.first(where: { $0.text == word }) else { return "" }
        let old = before.first { $0.text.caseInsensitiveCompare(word) == .orderedSame }
        if let spelling = now.heardAs.last(where: { !(old?.heardAs.contains($0) ?? false) }) {
            return "Humm will write it this way, not \u{201C}\(spelling)\u{201D}."
        }
        if let spelling = now.pending.last(where: { !(old?.pending.contains($0) ?? false) }) {
            return "Fix \u{201C}\(spelling)\u{201D} once more and Humm will change it by itself."
        }
        return "Humm will spell it this way from now on."
    }

    private func showLearned(_ notice: LearnedNotice) {
        noticeGeneration += 1
        learnedNotice = notice
        cue(.learned)
        onChange()
        let shown = noticeGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.noticeGeneration == shown else { return }
            self.closeLearned()
        }
    }

    func undoLearned() {
        guard let notice = learnedNotice else { return }
        dictionary.restore(notice.before)
        insights.recordLearned(-notice.words.count)
        Log.input.notice("dictionary: learning undone")
        closeLearned()
    }

    func closeLearned() {
        guard learnedNotice != nil else { return }
        noticeGeneration += 1
        learnedNotice = nil
        onChange()
    }

    // MARK: Open at Login

    func setOpenAtLogin(_ enabled: Bool) {
        if let message = LoginItem.set(enabled) {
            phase = LoginItem.needsApproval ? .notice(message) : .error(message)
        }
        Log.app.notice("open at login: \(LoginItem.isEnabled, privacy: .public)")
        onChange()
    }

    func cancelRecording() {
        guard phase == .recording else { return }
        recorder.cancel()
        cue(.stop)
        Log.app.notice("recording cancelled")
        phase = .idle
    }

    private func startRecording(mode: RecordingMode) {
        self.mode = mode
        closeTranscript()
        closeLearned()
        guard APIKeyStore.locate() != nil else {
            fail("No API key: choose Add API Key… in the Humm menu.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording()
        case .notDetermined:
            Task { [weak self] in
                let granted = await Recorder.requestPermission()
                guard let self else { return }
                guard granted else { return self.fail("Microphone access denied.") }
                // The keys were let go while macOS asked, so hold-to-talk cannot carry on.
                if self.mode == .handsFree {
                    self.beginRecording()
                } else {
                    self.phase = .notice("Microphone allowed. Hold ⌃ Ctrl + ⌥ Opt again to dictate.")
                }
            }
        default:
            fail("Microphone blocked. Allow Humm in Privacy & Security → Microphone.")
        }
    }

    private func beginRecording() {
        do {
            try recorder.start()
            cue(.start)
            phase = .recording
            // Learn from the last paste now, before this one is pasted.
            corrections.finish()
            // So an Electron app's text box can be found by the time the transcript is ready.
            if let app = NSWorkspace.shared.frontmostApplication {
                AX.askForTree(pid: app.processIdentifier, name: app.bundleIdentifier ?? "?")
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func finishRecording() {
        guard phase == .recording, let clip = recorder.stop() else { return }
        cue(.stop)
        Log.app.notice("recorded \(clip.duration, format: .fixed(precision: 1), privacy: .public)s")
        guard clip.duration >= Self.minimumDuration else {
            try? FileManager.default.removeItem(at: clip.url)
            phase = .idle
            return
        }
        transcribe(clip)
    }

    /// Sends a recording to OpenAI and delivers the text. The recording is deleted once it has
    /// been heard; if it could not be, it is kept for Try Again.
    private func transcribe(_ clip: (url: URL, duration: TimeInterval)) {
        guard let apiKey = APIKeyStore.locate()?.key else {
            try? FileManager.default.removeItem(at: clip.url)
            fail("No API key: choose Add API Key… in the Humm menu.")
            return
        }
        phase = .transcribing
        let stopped = Date()
        let model = model
        // The dictionary's spellings, and for the default model a request to write technical text as typed.
        let hint = TechnicalText.prompt(for: model, dictionaryHint: dictionary.hint(), technical: technicalFormatting)
        Task { [weak self] in
            do {
                let loudness = await Task.detached { Recorder.peakLoudness(of: clip.url) }.value
                if let loudness {
                    Log.app.notice("loudest \(Int(loudness), privacy: .public) dBFS")
                    if loudness < Self.silenceLevel {
                        try? FileManager.default.removeItem(at: clip.url)
                        self?.phase = .notice("Heard nothing to transcribe.")
                        return
                    }
                }
                let result = try await Transcriber.transcribe(fileURL: clip.url, model: model, apiKey: apiKey, prompt: hint)
                try? FileManager.default.removeItem(at: clip.url)  // heard: nothing to try again
                guard let self else { return }
                self.lastLatencyMs = Int(Date().timeIntervalSince(stopped) * 1000)
                // Billed whatever happens next, noise included.
                let cost = model.cost(of: result.usage, recordedSeconds: clip.duration)
                self.costs.add(cost, usage: result.usage, seconds: clip.duration, model: model)
                self.lastCost = cost
                var text = result.text
                guard !Transcriber.isNoise(text, hint: hint) else {
                    Log.app.notice("transcript dropped as noise")
                    self.phase = .notice("Heard nothing to transcribe.")
                    return
                }
                // Spelling first, so the dictionary's spellings and the snippets' text win.
                var spellingFixes = 0
                if self.britishSpelling {
                    let british = BritishSpelling.convertCounting(text)
                    text = british.text
                    spellingFixes = british.count
                }
                if self.technicalFormatting { text = TechnicalText.tidy(text).text }
                let applied = self.dictionary.applyCounting(to: text)
                text = applied.text
                let expanded = self.snippets.expand(text)
                if expanded.count > 0 { Log.app.notice("snippets: \(expanded.count, privacy: .public) expanded") }
                // Words as said: a snippet counts as its phrase.
                self.insights.record(words: Insights.wordCount(text), seconds: clip.duration,
                                     app: NSWorkspace.shared.frontmostApplication?.localizedName,
                                     dictionaryFixes: applied.fixes, spellingFixes: spellingFixes, snippets: expanded.count)
                text = expanded.text
                self.lastTranscript = text
                if Paster.isTrusted(prompt: false) {
                    let target = Focus.pasteTarget()
                    guard target != .other else {
                        Log.app.notice("no text box selected: offering the transcript to copy")
                        self.record(text, .offered, seconds: clip.duration, model: model, cost: cost)
                        self.phase = .idle
                        self.offerTranscript(text)
                        return
                    }
                    self.record(text, .pasted, seconds: clip.duration, model: model, cost: cost)
                    Paster.paste(text)
                    self.phase = .done
                    // A snippet's text is not what was said: nothing to learn from edits to it.
                    if expanded.count == 0 { self.corrections.watch(pasted: text) }
                } else {
                    self.record(text, .copied, seconds: clip.duration, model: model, cost: cost)
                    Paster.copy(text)
                    self.phase = .notice("Copied: press ⌘V. Allow Accessibility to auto-paste.")
                }
            } catch {
                guard let self else {
                    try? FileManager.default.removeItem(at: clip.url)
                    return
                }
                self.keepFailed(clip, reason: Transcriber.explain(error))
            }
        }
    }

    // MARK: Failed recordings

    private func keepFailed(_ clip: (url: URL, duration: TimeInterval), reason: String) {
        if let older = failedRecording, older.url != clip.url { try? FileManager.default.removeItem(at: older.url) }
        failedRecording = FailedRecording(url: clip.url, duration: clip.duration, reason: reason)
        Log.app.notice("transcription failed; recording kept for Try Again")
        fail(reason)
    }

    /// Sends the kept recording again.
    func retryFailedRecording() {
        guard let failed = failedRecording, phase != .recording, phase != .transcribing else { return }
        failedRecording = nil
        Log.input.notice("try again")
        transcribe((failed.url, failed.duration))
    }

    /// Deletes the kept recording: the card's close button, and quitting.
    func discardFailedRecording() {
        guard let failed = failedRecording else { return }
        try? FileManager.default.removeItem(at: failed.url)
        failedRecording = nil
        Log.input.notice("failed recording discarded")
        onChange()
    }

    private func fail(_ message: String) {
        cue(.failure)
        phase = .error(message)
    }

    private func cue(_ cue: Sounds.Cue) {
        if playSounds, !previewing { Sounds.play(cue) }  // developer previews stay silent
    }

    /// Confirmations, notices and errors clear themselves.
    private func scheduleReturnToIdle() {
        guard !previewing else { return }
        let lifetime: Duration
        switch phase {
        case .done: lifetime = .milliseconds(900)
        case .learned: lifetime = .seconds(4)
        case .copied: lifetime = .milliseconds(1200)
        case .notice, .error: lifetime = .seconds(6)
        default: return
        }
        let shown = phase
        Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            guard let self, self.phase == shown else { return }
            self.phase = .idle
        }
    }
}
