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

/// POST /v1/audio/transcriptions with a multipart upload.
enum Transcriber {
    private static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    /// `prompt` hints at spellings (see UserDictionary.hint).
    static func transcribe(fileURL: URL, model: TranscriptionModel, apiKey: String, prompt: String? = nil) async throws -> String {
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

        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let started = Date()
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        Log.net.notice("\(model.rawValue, privacy: .public) \(body.count, privacy: .public) bytes -> HTTP \(status, privacy: .public) in \(Int(Date().timeIntervalSince(started) * 1000), privacy: .public) ms")
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "request failed"
            throw HummError.api(status: status, message: String(message.prefix(200)))
        }
        return ((json?["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
