import Foundation

/// The user's dictionary: words Humm should spell a particular way, learned from corrections
/// (see CorrectionWatcher) or added by hand to ~/.config/humm/dictionary.json.
///
/// Words are used twice. They go to OpenAI as a spelling hint (the request's `prompt`), and each
/// word's `heardAs` spellings are replaced with it after transcription. The hint alone is not
/// enough for names that sound like ordinary words: in testing, gpt-4o-mini-transcribe kept
/// writing the ordinary word even with the name in the hint.
@MainActor
final class UserDictionary {
    struct Word: Codable, Equatable {
        /// The spelling to use.
        var text: String
        /// What the model wrote instead; replaced with `text` after transcription.
        var heardAs: [String] = []
        /// Ordinary words the model wrote instead ("planner" for "Plannr"), corrected once. They
        /// may be meant elsewhere, so they are replaced only after a second correction moves them
        /// to `heardAs`.
        var pending: [String] = []
        /// Spellings the user changed back after Humm replaced them. They are real words too, so
        /// they are no longer replaced.
        var keep: [String] = []
        /// Learned from a correction rather than added by hand.
        var learned = false
        var added = Date()
        /// Last learned or heard. The most recent words go into the hint first.
        var lastSeen = Date()

        init(text: String, heardAs: [String] = [], learned: Bool = false) {
            self.text = text
            self.heardAs = heardAs
            self.learned = learned
        }

        /// Lenient, for hand edits: a bare string, or an object with only "text".
        init(from decoder: Decoder) throws {
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                self.text = text
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            heardAs = try container.decodeIfPresent([String].self, forKey: .heardAs) ?? []
            pending = try container.decodeIfPresent([String].self, forKey: .pending) ?? []
            keep = try container.decodeIfPresent([String].self, forKey: .keep) ?? []
            learned = try container.decodeIfPresent(Bool.self, forKey: .learned) ?? false
            added = try container.decodeIfPresent(Date.self, forKey: .added) ?? Date()
            lastSeen = try container.decodeIfPresent(Date.self, forKey: .lastSeen) ?? added
        }
    }

    private struct Contents: Codable {
        var words: [Word]
    }

    nonisolated static let defaultFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/humm/dictionary.json")
    /// Longest hint sent with a recording, in characters. whisper-1 reads only the last 224
    /// tokens of it.
    private static let hintLimit = 600

    let file: URL
    private(set) var words: [Word] = []
    /// Set while the file cannot be read (e.g. a hand edit broke the JSON). Nothing is saved
    /// over it until it is fixed.
    private(set) var problem: String?
    private var loadedVersion: Date?

    init(file: URL = UserDictionary.defaultFile) {
        self.file = file
        load()
    }

    // MARK: Using the words

    /// Spelling hint for a transcription request: the most recently used words, or nil if none.
    func hint() -> String? {
        reloadIfChanged()
        var terms: [String] = []
        var length = 0
        for word in words.sorted(by: { $0.lastSeen > $1.lastSeen }) {
            length += word.text.count + 2
            guard length <= Self.hintLimit else { break }
            terms.append(word.text)
        }
        return terms.isEmpty ? nil : terms.joined(separator: ", ") + "."
    }

    /// Replaces spellings the model uses for dictionary words, and notes which words were heard.
    func apply(to transcript: String) -> String {
        var text = transcript
        let rules = words.flatMap { word in word.heardAs.map { (from: $0, to: word.text) } }
            .sorted { $0.from.count > $1.from.count }  // "super base" before "base"
        for rule in rules {
            text = Self.replacing(rule.from, with: rule.to, in: text)
        }
        let now = Date()
        var heard = false
        for index in words.indices where Self.contains(words[index].text, in: text) {
            words[index].lastSeen = now
            heard = true
        }
        if heard { save() }
        return text
    }

    // MARK: Learning

    /// Records corrections the user made to a pasted transcript. Returns the words that changed
    /// (new words, or new spellings of known ones) for the "Learned" confirmation.
    func learn(_ corrections: [Corrections.Candidate]) -> [String] {
        reloadIfChanged()
        var changed: [String] = []
        var dirty = false
        for correction in corrections {
            // Changed back to what the model wrote: that spelling is meant sometimes, so it is
            // never replaced (whether Humm replaced it or the hint alone changed it).
            if let entry = self.index(of: correction.from) {
                let before = words[entry].heardAs.count + words[entry].pending.count
                words[entry].heardAs.removeAll { Self.same($0, correction.to) }
                words[entry].pending.removeAll { Self.same($0, correction.to) }
                if words[entry].heardAs.count + words[entry].pending.count < before {
                    if !words[entry].keep.contains(where: { Self.same($0, correction.to) }) { words[entry].keep.append(correction.to) }
                    dirty = true
                    continue
                }
            }
            guard correction.isTerm else { continue }
            let spelling = correction.from
            // Never swap out another dictionary word.
            let spellingIsAWord = words.contains { Self.same($0.text, spelling) && $0.text != correction.to }
            let entry: Int
            if let known = self.index(of: correction.to) {
                entry = known
                words[entry].lastSeen = Date()
                dirty = true
                // The same word with other capitals. Take them only if there are more ("Github"
                // to "GitHub"): a known word typed in lower case ("plannr") is just typed fast.
                if words[entry].text != correction.to, Self.capitals(correction.to) > Self.capitals(words[entry].text) {
                    words[entry].heardAs.append(words[entry].text)
                    words[entry].text = correction.to
                    changed.append(correction.to)
                    continue
                }
            } else {
                words.append(Word(text: correction.to, learned: true))
                entry = words.count - 1
                dirty = true
                changed.append(correction.to)
            }
            let settled = words[entry].heardAs + words[entry].keep
            guard !spellingIsAWord, !settled.contains(where: { Self.same($0, spelling) }) else { continue }
            if let second = words[entry].pending.firstIndex(where: { Self.same($0, spelling) }) {
                words[entry].pending.remove(at: second)
                words[entry].heardAs.append(spelling)
            } else if correction.fromIsCommonWord {
                words[entry].pending.append(spelling)
            } else {
                words[entry].heardAs.append(spelling)
            }
            if changed.last != words[entry].text { changed.append(words[entry].text) }
        }
        if dirty { save() }
        return changed
    }

    /// Puts the words back as they were (Undo on the "Added to your dictionary" card).
    func restore(_ earlier: [Word]) {
        words = earlier
        save()
    }

    func remove(_ text: String) {
        reloadIfChanged()
        words.removeAll { $0.text == text }
        save()
    }

    // MARK: File

    /// Picks up hand edits to the file.
    func reloadIfChanged() {
        guard modificationDate != loadedVersion else { return }
        load()
    }

    private var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    private func load() {
        loadedVersion = modificationDate
        guard let data = try? Data(contentsOf: file) else {
            words = []
            problem = nil
            return
        }
        do {
            words = try Self.decoder.decode(Contents.self, from: data).words
            problem = nil
        } catch {
            problem = "Can't read \((file.path as NSString).abbreviatingWithTildeInPath): fix or delete it."
            Log.app.error("dictionary unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        guard problem == nil else { return }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try Self.encoder.encode(Contents(words: words)).write(to: file, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            loadedVersion = modificationDate
        } catch {
            Log.app.error("dictionary not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Creates an empty dictionary file if there is none, so it can be opened and edited.
    func createFileIfMissing() {
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        save()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: Matching

    private func index(of text: String) -> Int? {
        words.firstIndex { Self.same($0.text, text) }
    }

    private static func capitals(_ text: String) -> Int {
        text.filter(\.isUppercase).count
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }

    /// Whole-word, case-insensitive pattern for a phrase; its words may be split by spaces or hyphens.
    /// Snippets match their phrases the same way.
    static func phrasePattern(_ phrase: String) -> NSRegularExpression? {
        let words = phrase.split { $0 == " " || $0 == "-" }.map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !words.isEmpty else { return nil }
        let body = words.joined(separator: "[\\s-]+")
        return try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])\(body)(?![\\p{L}\\p{N}])", options: .caseInsensitive)
    }

    static func replacing(_ phrase: String, with replacement: String, in text: String) -> String {
        guard let regex = phrasePattern(phrase) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }

    private static func contains(_ phrase: String, in text: String) -> Bool {
        phrasePattern(phrase)?.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }
}
