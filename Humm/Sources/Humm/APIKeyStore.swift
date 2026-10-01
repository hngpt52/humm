import Foundation

/// Reads OPENAI_API_KEY from ~/.config/humm/.env (mode 0600; `scripts/install-key.sh` fills it).
/// Only that file: macOS guards ~/Desktop and ~/Documents, and reading a .env there makes
/// the read block on a privacy prompt, which froze the app on launch. No Keychain either:
/// an ad-hoc signed app gets a new identity on every rebuild and the Keychain prompts again.
enum APIKeyStore {
    static let userFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/humm/.env")

    static func apiKey() -> String? { locate()?.key }

    /// The key and the file it came from.
    static func locate() -> (key: String, file: URL)? {
        read(userFile).map { ($0, userFile) }
    }

    /// Creates ~/.config/humm/.env (mode 0600) with an empty OPENAI_API_KEY line to fill in.
    static func createUserFileIfMissing() -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: userFile.path) {
            try? fm.createDirectory(at: userFile.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
            fm.createFile(atPath: userFile.path, contents: Data("OPENAI_API_KEY=\n".utf8),
                          attributes: [.posixPermissions: 0o600])
        }
        return userFile
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
