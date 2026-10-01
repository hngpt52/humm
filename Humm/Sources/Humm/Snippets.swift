import Foundation
import Observation

/// A phrase that, said while dictating, types something longer instead: "my calendar link" for
/// the link itself, "sign off" for a signature.
struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    /// What to say.
    var trigger: String
    /// What Humm types instead. May run over several lines.
    var text: String
}

/// The user's snippets, in ~/.config/humm/snippets.json (private to the user).
@MainActor
@Observable
final class SnippetStore {
    nonisolated static let defaultFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/humm/snippets.json")

    enum Problem: Equatable {
        case shortTrigger, emptyText, duplicate

        var message: String {
            switch self {
            case .shortTrigger: "Give the phrase to say at least two letters."
            case .emptyText: "Add the text to type."
            case .duplicate: "Another snippet already uses that phrase."
            }
        }
    }

    private struct Contents: Codable {
        var snippets: [Snippet]
    }

    let file: URL
    /// Sorted by phrase.
    private(set) var snippets: [Snippet] = []

    init(file: URL = SnippetStore.defaultFile) {
        self.file = file
        load()
    }

    func contains(_ id: Snippet.ID) -> Bool {
        snippets.contains { $0.id == id }
    }

    /// Adds a snippet or updates one with the same id; says what is wrong instead if it can't.
    @discardableResult
    func save(_ snippet: Snippet) -> Problem? {
        let trigger = Self.normalise(snippet.trigger)
        guard trigger.count >= 2 else { return .shortTrigger }
        guard !snippet.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .emptyText }
        guard !snippets.contains(where: { $0.id != snippet.id && $0.trigger.caseInsensitiveCompare(trigger) == .orderedSame }) else {
            return .duplicate
        }
        var snippet = snippet
        snippet.trigger = trigger
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else {
            snippets.append(snippet)
        }
        snippets.sort { $0.trigger.localizedCaseInsensitiveCompare($1.trigger) == .orderedAscending }
        write()
        return nil
    }

    func remove(_ id: Snippet.ID) {
        snippets.removeAll { $0.id == id }
        write()
    }

    /// Types each snippet whose phrase was said, in place of the phrase. A transcript that is
    /// only the phrase becomes only the snippet, without a stray full stop. Returns the text and
    /// how many phrases were replaced.
    func expand(_ transcript: String) -> (text: String, count: Int) {
        guard !snippets.isEmpty else { return (transcript, 0) }
        let bare = Self.normalise(transcript.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)))
        if let only = snippets.first(where: { $0.trigger.caseInsensitiveCompare(bare) == .orderedSame }) {
            return (only.text, 1)
        }
        // Mark each phrase first and fill the marks in at the end, so the text of one snippet is
        // never taken for the phrase of another. Longer phrases first ("sign off formally" before
        // "sign off"). The marks are private-use characters, which no phrase can match.
        var text = transcript
        var count = 0
        let longestFirst = snippets.indices.sorted { snippets[$0].trigger.count > snippets[$1].trigger.count }
        for index in longestFirst {
            guard let regex = UserDictionary.phrasePattern(snippets[index].trigger) else { continue }
            let range = NSRange(location: 0, length: (text as NSString).length)
            let found = regex.numberOfMatches(in: text, range: range)
            guard found > 0 else { continue }
            count += found
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: Self.mark(index))
        }
        for index in snippets.indices where count > 0 {
            text = text.replacingOccurrences(of: Self.mark(index), with: snippets[index].text)
        }
        return (text, count)
    }

    private static func mark(_ index: Int) -> String {
        "\u{E000}" + String(Character(UnicodeScalar(0xE100 + index % 0x0E00)!)) + "\u{E001}"
    }

    /// Single spaces, no space at either end.
    private static func normalise(_ phrase: String) -> String {
        phrase.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: File

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        do {
            snippets = try JSONDecoder().decode(Contents.self, from: data).snippets
        } catch {
            let aside = file.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: aside)
            Log.app.error("snippets unreadable, moved aside: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func write() {
        let fm = FileManager.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        do {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try encoder.encode(Contents(snippets: snippets)).write(to: file, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            Log.app.error("snippets not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
