import Foundation

/// Finds words the user corrected in text Humm pasted. Only small swaps of similar-looking words
/// count ("planner" to "Plannr", "super base" to "Supabase"); rewrites, deletions and new
/// sentences typed around the paste are ignored.
enum Corrections {
    struct Candidate: Equatable {
        /// As transcribed, e.g. "super base".
        let from: String
        /// As corrected, e.g. "Supabase".
        let to: String
        /// Looks like a name or term rather than a grammar fix: a word the spelling dictionary does
        /// not know, capitals inside a word, digits, or a capital added mid-sentence.
        let isTerm: Bool
        /// `from` is a single ordinary word ("planner"), which may well be meant elsewhere.
        let fromIsCommonWord: Bool
        /// Where the edited words sit in the edited text (UTF-16), to tell whether the caret is
        /// still in them, i.e. the user may still be typing.
        let range: NSRange
    }

    struct Result {
        /// False once the pasted text is no longer there: sent, cleared or rewritten.
        let found: Bool
        let candidates: [Candidate]
        /// Pasted words still there, of all of them (for the log).
        var kept = 0
        var pasted = 0
    }

    private struct Token {
        let text: String
        /// Lowercased letters and digits only, for matching.
        let key: String
        /// UTF-16 range in the text it came from.
        let range: NSRange
    }

    /// Longest correction learned, in words, on either side.
    private static let maxWords = 3
    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:!?\"'“”‘’()[]{}…")

    /// `before` and `after` are the text either side of the paste when it happened; `edited` is
    /// the same stretch of the field now.
    static func find(pasted: String, before: String, after: String, edited: String,
                     isKnownWord: (String) -> Bool) -> Result {
        let head = tokens(before)
        let span = tokens(pasted)
        let old = head + span + tokens(after)
        let new = tokens(edited)
        let pasteRange = head.count..<(head.count + span.count)
        guard !span.isEmpty else { return Result(found: false, candidates: []) }

        let pairs = align(old.map(\.key), new.map(\.key))
        let kept = pairs.filter { pasteRange.contains($0.0) }.count
        // Gone: the field was emptied (a message sent, say), or most of a longer paste vanished.
        // A paste of one or two words being retyped is not gone: fixing one of its words changes
        // half of it or more.
        guard !new.isEmpty, span.count < 3 || kept * 2 >= span.count else {
            return Result(found: false, candidates: [], kept: kept, pasted: span.count)
        }

        // Anchors are words that came through untouched. A word whose capitals changed belongs to
        // the correction next to it ("Claro lens" to "Klaro Lens"), or is one on its own.
        let anchors = pairs.filter { phrase([old[$0.0]]) == phrase([new[$0.1]]) }
        // Each gap between anchors is some words removed and some inserted.
        var candidates: [Candidate] = []
        var replaced = 0
        let bounds = [(-1, -1)] + anchors + [(old.count, new.count)]
        for (previous, next) in zip(bounds, bounds.dropFirst()) {
            let removed = (previous.0 + 1)..<next.0
            let inserted = (previous.1 + 1)..<next.1
            guard !removed.isEmpty, !inserted.isEmpty else { continue }
            guard removed.allSatisfy(pasteRange.contains) else { continue }  // not Humm's text
            replaced += removed.count
            guard removed.count <= maxWords else { continue }
            if let candidate = candidate(Array(old[removed]), Array(new[inserted]), in: edited, isKnownWord: isKnownWord) {
                candidates.append(candidate)
            }
        }
        // Many words replaced is a rewrite, not corrections.
        guard replaced <= max(3, span.count * 3 / 10) else {
            return Result(found: true, candidates: [], kept: kept, pasted: span.count)
        }
        return Result(found: true, candidates: candidates, kept: kept, pasted: span.count)
    }

    /// The removed words and the stretch of inserted words that best matches them, if they are
    /// close enough to be the same words misheard.
    private static func candidate(_ removed: [Token], _ inserted: [Token], in edited: String,
                                  isKnownWord: (String) -> Bool) -> Candidate? {
        let fromKey = removed.map(\.key).joined()
        // Words typed next to a correction are not part of it: pick the closest stretch.
        var best: (words: ArraySlice<Token>, distance: Int)?
        for length in 1...min(maxWords, inserted.count) {
            for start in 0...(inserted.count - length) {
                let words = inserted[start..<(start + length)]
                let distance = distance(fromKey, words.map(\.key).joined())
                if best == nil || distance < best!.distance { best = (words, distance) }
            }
        }
        guard let best else { return nil }
        let toKey = best.words.map(\.key).joined()
        guard best.distance <= max(1, max(fromKey.count, toKey.count) / 2) else { return nil }
        // Part of the word is gone: still being deleted or retyped.
        guard !(fromKey.hasPrefix(toKey) && fromKey != toKey) else { return nil }

        let from = phrase(removed)
        let to = phrase(Array(best.words))
        guard !from.isEmpty, !to.isEmpty, from != to else { return nil }
        let atSentenceStart = startsSentence(at: best.words.first!.range.location, in: edited)
        let capitalAdded = !atSentenceStart && isCapitalised(to) && !isCapitalised(from) && toKey.count >= 4
        let isTerm: Bool
        if plain(from) == plain(to) {
            // Only capitals or punctuation changed: a term only for "Github" to "GitHub" or a
            // name capitalised mid-sentence.
            isTerm = to.split(separator: " ").contains(where: hasInnerCapital) || capitalAdded
        } else {
            isTerm = looksLikeTerm(to, isKnownWord: isKnownWord) || capitalAdded
        }
        let common = removed.count == 1 && isKnownWord(String(from.filter(\.isLetter)))
        let start = inserted.first!.range.location
        let end = NSMaxRange(inserted.last!.range)
        return Candidate(from: from, to: to, isTerm: isTerm, fromIsCommonWord: common,
                         range: NSRange(location: start, length: end - start))
    }

    private static func looksLikeTerm(_ text: String, isKnownWord: (String) -> Bool) -> Bool {
        text.split(separator: " ").contains { word in
            if word.contains(where: \.isNumber) || hasInnerCapital(word) { return true }
            let letters = String(word.filter(\.isLetter))
            return !letters.isEmpty && !isKnownWord(letters)
        }
    }

    private static func hasInnerCapital(_ word: Substring) -> Bool {
        word.dropFirst().contains(where: \.isUppercase)
    }

    private static func isCapitalised(_ text: String) -> Bool {
        text.first(where: \.isLetter)?.isUppercase ?? false
    }

    /// Lowercased letters, digits and single spaces.
    private static func plain(_ text: String) -> String {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.joined(separator: " ")
    }

    private static func phrase(_ words: [Token]) -> String {
        words.map(\.text).joined(separator: " ").trimmingCharacters(in: edgePunctuation)
    }

    /// Whether the word at `location` begins a sentence: nothing, a line break or . ! ? before it.
    private static func startsSentence(at location: Int, in text: String) -> Bool {
        let characters = text as NSString
        var index = location - 1
        while index >= 0 {
            let character = characters.character(at: index)
            switch character {
            case 0x20, 0x09, 0xA0: index -= 1  // spaces
            case 0x0A, 0x0D, 0x2E, 0x21, 0x3F: return true  // line break . ! ?
            default: return false
            }
        }
        return true
    }

    private static func tokens(_ text: String) -> [Token] {
        let characters = text as NSString
        let words = try! NSRegularExpression(pattern: "\\S+")
        return words.matches(in: text, range: NSRange(location: 0, length: characters.length)).compactMap { match in
            let word = characters.substring(with: match.range)
            let key = String(word.lowercased().filter { $0.isLetter || $0.isNumber })
            return key.isEmpty ? nil : Token(text: word, key: key, range: match.range)
        }
    }

    /// Longest common subsequence of two word lists, as pairs of matching indices.
    private static func align(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let n = a.count, m = b.count
        var lengths = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lengths[i][j] = a[i] == b[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] {
                pairs.append((i, j))
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }

    /// Edit distance between two strings.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
