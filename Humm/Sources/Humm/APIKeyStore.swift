import Foundation

/// Reads OPENAI_API_KEY from ~/.config/humm/.env (mode 0600), which the Add API Key… prompt or
/// `scripts/install-key.sh` fills. Only that file: macOS guards ~/Desktop and ~/Documents, and
/// reading a .env there makes the read block on a privacy prompt, which froze the app on launch.
/// No Keychain either: an ad-hoc signed app gets a new identity on every rebuild and the Keychain
/// prompts again.
enum APIKeyStore {
    static let userFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/humm/.env")

    static func apiKey() -> String? { locate()?.key }

    /// The key and the file it came from.
    static func locate(in file: URL = userFile) -> (key: String, file: URL)? {
        read(file).map { ($0, file) }
    }

    /// Roughly what an OpenAI API key looks like, to catch something else pasted by mistake.
    static func isPlausible(_ key: String) -> Bool {
        key.hasPrefix("sk-") && key.count >= 20 && !key.contains(where: \.isWhitespace)
    }

    /// Saves the key, replacing any OPENAI_API_KEY line and keeping the rest of the file. The
    /// folder is private to the user (0700) and the file readable only by them (0600).
    static func save(_ key: String, to file: URL = userFile) throws {
        let fm = FileManager.default
        let folder = file.deletingLastPathComponent()
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let others = ((try? String(contentsOf: file, encoding: .utf8)) ?? "")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { line in
                let line = line.trimmingCharacters(in: .whitespaces)
                return !line.hasPrefix("OPENAI_API_KEY") && !line.hasPrefix("export OPENAI_API_KEY")
            }
        try Data((others + ["OPENAI_API_KEY=\(key)"]).joined(separator: "\n").appending("\n").utf8).write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private static func read(_ file: URL) -> String? {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for raw in contents.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard line.hasPrefix("OPENAI_API_KEY"), let eq = line.firstIndex(of: "=") else { continue }
            let value = line[line.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return value }
        }
        return nil
    }
}
