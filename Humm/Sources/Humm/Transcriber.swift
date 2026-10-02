import AVFoundation
import Foundation

enum TranscriptionModel: String, CaseIterable, Identifiable {
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case whisper1 = "whisper-1"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .gpt4oMiniTranscribe: "GPT-4o mini Transcribe (~$0.003/min)"
        case .whisper1: "Whisper (~$0.006/min)"
        }
    }
}

enum HummError: LocalizedError {
    case recordingFailed
    case missingAPIKey
    case api(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .recordingFailed: "Could not start recording."
        case .missingAPIKey: "Set your OpenAI API key first."
        case let .api(status, message): "OpenAI \(status): \(message)"
        }
    }
}

struct Transcription {
    let text: String
    /// What OpenAI reported the request used; nil if the response did not say.
    let usage: Usage?
}

/// POST /v1/audio/transcriptions with a multipart upload.
enum Transcriber {
    /// Changed only by `--selftest --endpoint`, to test against a local stand-in.
    static var endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    /// `prompt` hints at spellings (see UserDictionary.hint).
    static func transcribe(fileURL: URL, model: TranscriptionModel, apiKey: String, prompt: String? = nil) async throws -> Transcription {
        let boundary = "humm-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model.rawValue)
        field("response_format", "json")
        if let prompt, !prompt.isEmpty { field("prompt", prompt) }
        let ext = fileURL.pathExtension.lowercased()
        let mime = ["m4a": "audio/mp4", "wav": "audio/wav", "mp3": "audio/mpeg", "webm": "audio/webm"][ext] ?? "application/octet-stream"
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.\(ext)\"\r\nContent-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // Replies take 1 to 5 s (median 1.1 s over 96 requests), so one still waiting long past
        // that is lost: it is abandoned and sent once more, on a new connection.
        let limit = 15 + audioSeconds(fileURL) * 0.1
        var request = URLRequest(url: endpoint, timeoutInterval: limit)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var attempt = 1
        while true {
            let started = Date()
            do {
                return try await send(request, body: body, model: model, limit: limit)
            } catch {
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                Log.net.error("\(model.rawValue, privacy: .public) attempt \(attempt, privacy: .public) failed after \(ms, privacy: .public) ms: \(Self.code(of: error), privacy: .public)")
                guard attempt < 2, isWorthRetrying(error) else { throw error }
                attempt += 1
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// One attempt on a connection of its own. A connection kept open from an earlier request
    /// can die without a word (twice through a VPN tunnel, after two or three idle minutes) and
    /// swallow the next request whole; a new one costs about a tenth of a second.
    private static func send(_ request: URLRequest, body: Data, model: TranscriptionModel, limit: TimeInterval) async throws -> Transcription {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = limit
        configuration.timeoutIntervalForResource = limit
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let started = Date()
        let (data, response) = try await session.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        Log.net.notice("\(model.rawValue, privacy: .public) \(body.count, privacy: .public) bytes -> HTTP \(status, privacy: .public) in \(Int(Date().timeIntervalSince(started) * 1000), privacy: .public) ms")
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "request failed"
            throw HummError.api(status: status, message: String(message.prefix(200)))
        }
        return Transcription(text: ((json?["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                             usage: Usage(json: json?["usage"]))
    }

    /// Worth one more try: no reply, a dropped or failed connection, or OpenAI busy or failing.
    /// Not a refused key or a bad request, which would only fail again.
    static func isWorthRetrying(_ error: Error) -> Bool {
        if case let HummError.api(status, _) = error { return status == 429 || status >= 500 }
        guard let error = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                .notConnectedToInternet, .secureConnectionFailed, .badServerResponse].contains(error.code)
    }

    /// What went wrong, in words for the pill and the card.
    static func explain(_ error: Error) -> String {
        guard let error = error as? URLError else { return error.localizedDescription }
        switch error.code {
        case .timedOut: return "OpenAI didn't reply in time."
        case .notConnectedToInternet: return "No internet connection."
        case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .secureConnectionFailed:
            return "Couldn't reach OpenAI."
        default: return error.localizedDescription
        }
    }

    /// For the log: codes only. OpenAI's messages can quote part of the key.
    private static func code(of error: Error) -> String {
        if case let HummError.api(status, _) = error { return "HTTP \(status)" }
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }

    /// Length of the recording, to allow longer ones more time.
    private static func audioSeconds(_ file: URL) -> Double {
        guard let audio = try? AVAudioFile(forReading: file), audio.fileFormat.sampleRate > 0 else { return 60 }
        return Double(audio.length) / audio.fileFormat.sampleRate
    }

    /// Transcripts that are not speech. Given silence, gpt-4o-mini-transcribe repeats the hint back
    /// word for word, and whisper-1 writes stock phrases.
    static func isNoise(_ text: String, hint: String?) -> Bool {
        let said = plainWords(text)
        guard !said.isEmpty else { return true }
        if ["you", "ご視聴ありがとうございました"].contains(said) { return true }
        guard let hint else { return false }
        // Two or more of the hint's words, in the hint's order, and nothing else.
        let terms = hint.split(separator: ",").map { plainWords(String($0)) }.filter { !$0.isEmpty }
        let heard = terms.filter { " \(said) ".contains(" \($0) ") }
        return " \(plainWords(hint)) ".contains(" \(said) ") && heard.count >= 2
    }

    /// Lowercased letters and digits, words separated by single spaces.
    private static func plainWords(_ text: String) -> String {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.joined(separator: " ")
    }
}
