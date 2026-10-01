import Foundation
import Observation

/// One dictation, as it was delivered.
struct Transcript: Codable, Identifiable, Equatable {
    enum Outcome: String, Codable {
        /// Pasted into the app in front.
        case pasted
        /// No text box was selected, so it was offered in the copy card.
        case offered
        /// Copied to the clipboard, because Humm may not paste (no Accessibility permission).
        case copied
    }

    var id = UUID()
    let text: String
    /// To the whole second, as the file stores it, so a transcript reads back equal.
    var date = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    /// The app in front when it was ready: where it was pasted, or where there was no text box.
    let app: String?
    let outcome: Outcome
    /// Length of the recording, in seconds.
    let seconds: Double
    let model: String
    /// What the transcription cost, in US dollars (see CostTracker). Older entries have none.
    var cost: Double? = nil
}

/// Past transcripts, newest first, in ~/.config/humm/history.json (private to the user), so they
/// can be found and copied again. Never logged.
@MainActor
@Observable
final class TranscriptHistory {
    nonisolated static let defaultFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/humm/history.json")
    /// Older transcripts beyond this many are dropped.
    static let limit = 1000

    private struct Contents: Codable {
        var transcripts: [Transcript]
    }

    let file: URL
    private(set) var entries: [Transcript] = []

    init(file: URL = TranscriptHistory.defaultFile) {
        self.file = file
        load()
    }

    func add(_ transcript: Transcript) {
        entries.insert(transcript, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    func remove(_ id: Transcript.ID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Deletes every transcript, and the file.
    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: file)
    }

    /// Transcripts containing `query`, ignoring case and accents; all of them for an empty query.
    func matching(_ query: String) -> [Transcript] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? entries : entries.filter { $0.text.localizedStandardContains(query) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        do {
            entries = try Self.decoder.decode(Contents.self, from: data).transcripts
        } catch {
            // Keep the unreadable file rather than saving over it.
            let aside = file.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: aside)
            Log.app.error("history unreadable, moved aside: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try Self.encoder.encode(Contents(transcripts: entries)).write(to: file, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            Log.app.error("history not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
