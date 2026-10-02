import Foundation

/// Writes spoken technical text the way it is typed: paths, flags, snake_case names and sizes
/// ("a 1.2 gigabyte .next slash dev folder" becomes "a 1.2 GB .next/dev folder").
///
/// gpt-4o-mini-transcribe does most of this when the prompt asks (`styleHint`); `tidy` catches
/// what it misses. Tested on read-out sentences: with the hint it wrote ~/Library/Application
/// Support, --force and 2 GB where it otherwise spelt them out, and still left "slash the
/// budget" and "on the dot of nine" alone. whisper-1 garbles paths with the hint
/// (~~/.library/.application.support), so it only goes to gpt-4o-mini-transcribe.
enum TechnicalText {
    static let styleHint = "Technical dictation: write file paths, file names, command-line flags and sizes in their written form, for example ~/Downloads/report.pdf, lib/utils.ts, --force, 3 MB."

    /// The prompt for a request: the style hint (when on, for the model it suits) and the
    /// dictionary's spelling hint.
    static func prompt(for model: TranscriptionModel, dictionaryHint: String?, technical: Bool) -> String? {
        let parts = [technical && model == .gpt4oMiniTranscribe ? styleHint : nil, dictionaryHint].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The text tidied, and how many changes that made. Cautious on purpose: words around "slash"
    /// are only joined after something that already looks like a path, and sizes only with a number.
    static func tidy(_ text: String) -> (text: String, count: Int) {
        var text = text
        var count = 0
        func replace(_ pattern: String, _ template: String, caseSensitive: Bool = false) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : .caseInsensitive) else { return }
            let range = NSRange(location: 0, length: (text as NSString).length)
            count += regex.numberOfMatches(in: text, range: range)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
        }
        // Sizes: "1.2 gigabyte" and "a 2-gigabyte file" to 1.2 GB and 2 GB; "2TB" to 2 TB.
        for (prefix, unit) in [("kilo", "KB"), ("mega", "MB"), ("giga", "GB"), ("tera", "TB"), ("peta", "PB")] {
            replace("(\\d+(?:\\.\\d+)?)[\\s-]*\(prefix)bytes?\\b", "$1 \(unit)")
        }
        replace("(\\d)(KB|MB|GB|TB|PB)\\b", "$1 $2", caseSensitive: true)
        // Flags and snake_case.
        replace("\\bdash[\\s-]dash ([a-z][\\w-]*)", "--$1")
        replace("(\\w+) underscore (?=\\w)", "$1_")
        // Paths: "slash" after something path-like joins it to the next word, so a chain
        // (".next slash dev slash cache") becomes one path.
        var words = text.components(separatedBy: " ")
        var index = 1
        while index < words.count - 1 {
            if words[index].lowercased() == "slash", looksLikePath(words[index - 1]) {
                words[index - 1] += "/" + words[index + 1]
                words.removeSubrange(index...(index + 1))
                count += 1
            } else {
                index += 1
            }
        }
        return (words.joined(separator: " "), count)
    }

    /// Already a path or a file: has a slash, starts with ~ or a dot, or has a dot inside it
    /// (page.tsx), not just a full stop at the end.
    private static func looksLikePath(_ word: String) -> Bool {
        let core = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'()[]{},;:!?"))
        if core == "~" { return true }
        guard core.count > 1 else { return false }
        if core.contains("/") || core.hasPrefix("~") || core.hasPrefix(".") { return true }
        return core.dropLast().contains(".") && !core.hasSuffix(".")
    }
}
