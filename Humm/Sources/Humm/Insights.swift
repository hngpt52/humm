import Foundation
import Observation

/// What Humm has been used for, per day: dictations, words, speaking time, the fixes it made and
/// the apps dictated into, in ~/.config/humm/insights.json (private to the user). Counts and app
/// names only, never what was said. Kept for good, unlike History.
@MainActor
@Observable
final class Insights {
    nonisolated static let defaultFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/humm/insights.json")
    /// A typing speed to compare speaking with, in words per minute.
    nonisolated static let typingSpeed = 40.0

    struct Day: Codable, Equatable {
        /// The day on this Mac's calendar, "2026-10-01".
        let date: String
        var dictations = 0
        /// Words said: a snippet counts as its phrase, not the text it becomes.
        var words = 0
        /// Length of the recordings, pauses included.
        var seconds: Double = 0
        /// Misheard spellings the dictionary replaced.
        var dictionaryFixes = 0
        /// American spellings made British.
        var spellingFixes = 0
        var snippets = 0
        /// Words added to the dictionary from corrections.
        var wordsLearned = 0
        /// Dictations and words per app, by the app's name.
        var apps: [String: AppUse] = [:]
    }

    struct AppUse: Codable, Equatable {
        var dictations = 0
        var words = 0
    }

    /// Kinds of app, told apart by name.
    enum Category: String, CaseIterable {
        case aiPrompts = "AI prompts"
        case personalMessages = "Personal messages"
        case workMessages = "Work messages"
        case emails = "Emails"
        case documents = "Documents"
        case other = "Other"
    }

    struct Summary: Equatable {
        var dictations = 0
        var words = 0
        var seconds: Double = 0
        var dictionaryFixes = 0
        var spellingFixes = 0
        var snippets = 0
        var wordsLearned = 0

        var fixes: Int { dictionaryFixes + spellingFixes + snippets }
        /// Words over recording time, pauses included.
        var wordsPerMinute: Double? { seconds > 0 ? Double(words) / (seconds / 60) : nil }
        /// Typing the same words at `typingSpeed`, less the time spent speaking.
        var minutesSaved: Double { max(0, Double(words) / Insights.typingSpeed - seconds / 60) }
    }

    /// `lastMonthSoFar` is last month up to the same day of the month as today, to compare a
    /// month in progress fairly.
    enum Period { case allTime, thisMonth, lastMonth, lastMonthSoFar }

    private struct Contents: Codable {
        var days: [Day]
    }

    let file: URL
    private(set) var days: [Day] = []
    /// No file yet: nothing recorded on this Mac before.
    private(set) var isNew = false

    init(file: URL = Insights.defaultFile) {
        self.file = file
        load()
    }

    // MARK: Recording

    func record(words: Int, seconds: Double, app: String?, dictionaryFixes: Int, spellingFixes: Int, snippets: Int, at date: Date = Date()) {
        update(date) { day in
            day.dictations += 1
            day.words += words
            day.seconds += seconds
            day.dictionaryFixes += dictionaryFixes
            day.spellingFixes += spellingFixes
            day.snippets += snippets
            if let app, !app.isEmpty {
                day.apps[app, default: AppUse()].dictations += 1
                day.apps[app, default: AppUse()].words += words
            }
        }
    }

    /// Words learned from corrections; negative when learning is undone.
    func recordLearned(_ count: Int, at date: Date = Date()) {
        guard count != 0 else { return }
        update(date) { $0.wordsLearned = max(0, $0.wordsLearned + count) }
    }

    /// Fills a new file from the transcripts History has kept, so Insights starts with them.
    /// Their fixes were not counted, so those start at nothing.
    func seed(from transcripts: [Transcript]) {
        guard days.isEmpty, !transcripts.isEmpty else { return }
        for transcript in transcripts.reversed() {
            let words = Self.wordCount(transcript.text)
            update(transcript.date, saving: false) { day in
                day.dictations += 1
                day.words += words
                day.seconds += transcript.seconds
                if let app = transcript.app, !app.isEmpty {
                    day.apps[app, default: AppUse()].dictations += 1
                    day.apps[app, default: AppUse()].words += words
                }
            }
        }
        save()
    }

    private func update(_ date: Date, saving: Bool = true, _ change: (inout Day) -> Void) {
        let key = CostTracker.dayKey(date)
        if let index = days.firstIndex(where: { $0.date == key }) {
            change(&days[index])
        } else {
            var day = Day(date: key)
            change(&day)
            days.append(day)
            days.sort { $0.date < $1.date }
        }
        if saving { save() }
    }

    // MARK: Reading

    func summary(_ period: Period, now: Date = Date()) -> Summary {
        let lastMonth = String(CostTracker.dayKey(CostTracker.calendar.date(byAdding: .month, value: -1, to: now) ?? now).prefix(7))
        let prefix = switch period {
        case .allTime: ""
        case .thisMonth: String(CostTracker.dayKey(now).prefix(7))
        case .lastMonth, .lastMonthSoFar: lastMonth
        }
        let lastDay = period == .lastMonthSoFar ? String(CostTracker.dayKey(now).suffix(2)) : "31"
        return days.filter { $0.date.hasPrefix(prefix) && $0.date.suffix(2) <= lastDay }.reduce(into: Summary()) { total, day in
            total.dictations += day.dictations
            total.words += day.words
            total.seconds += day.seconds
            total.dictionaryFixes += day.dictionaryFixes
            total.spellingFixes += day.spellingFixes
            total.snippets += day.snippets
            total.wordsLearned += day.wordsLearned
        }
    }

    /// Every app dictated into, most words first.
    func apps() -> [(name: String, use: AppUse)] {
        var totals: [String: AppUse] = [:]
        for day in days {
            for (name, use) in day.apps {
                totals[name, default: AppUse()].dictations += use.dictations
                totals[name, default: AppUse()].words += use.words
            }
        }
        return totals.map { (name: $0.key, use: $0.value) }
            .sorted { $0.use.words != $1.use.words ? $0.use.words > $1.use.words : $0.name < $1.name }
    }

    /// Dictations per kind of app, every kind listed, in a fixed order.
    func categories() -> [(category: Category, dictations: Int)] {
        var counts: [Category: Int] = [:]
        for app in apps() { counts[Self.category(of: app.name), default: 0] += app.use.dictations }
        return Category.allCases.map { (category: $0, dictations: counts[$0] ?? 0) }
    }

    /// Days in a row with a dictation, up to today, or up to yesterday until today has one.
    func currentStreak(now: Date = Date()) -> Int {
        let active = activeDays
        var key = CostTracker.dayKey(now)
        if !active.contains(key) { key = Self.dayBefore(key) }
        var streak = 0
        while active.contains(key) {
            streak += 1
            key = Self.dayBefore(key)
        }
        return streak
    }

    func longestStreak() -> Int {
        let active = activeDays
        var longest = 0
        for key in active where !active.contains(Self.dayBefore(key)) {  // each run's first day
            var length = 0
            var day = key
            while active.contains(day) {
                length += 1
                day = Self.dayAfter(day)
            }
            longest = max(longest, length)
        }
        return longest
    }

    func words(on key: String) -> Int { days.first { $0.date == key }?.words ?? 0 }

    /// The first day with a dictation.
    var firstDay: Date? { days.first { $0.dictations > 0 }.flatMap { CostTracker.date(fromKey: $0.date) } }

    private var activeDays: Set<String> { Set(days.filter { $0.dictations > 0 }.map(\.date)) }

    // MARK: Helpers

    nonisolated static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).filter { $0.contains { $0.isLetter || $0.isNumber } }.count
    }

    nonisolated static func category(of app: String) -> Category {
        let name = app.lowercased()
        let kinds: [(Category, [String])] = [
            (.aiPrompts, ["claude", "chatgpt", "perplexity", "gemini", "copilot", "cursor", "windsurf", "le chat", "grok"]),
            (.personalMessages, ["messages", "whatsapp", "telegram", "signal", "messenger", "discord", "instagram"]),
            (.workMessages, ["slack", "teams", "google chat", "webex", "mattermost"]),
            (.emails, ["mail", "outlook", "spark", "superhuman", "airmail", "mimestream", "canary mail", "thunderbird", "hey"]),
            (.documents, ["notes", "textedit", "pages", "word", "obsidian", "notion", "bear", "craft", "ulysses", "ia writer", "scrivener"]),
        ]
        for (category, names) in kinds where names.contains(where: { name == $0 || name.hasPrefix($0 + " ") || name.hasSuffix(" " + $0) }) {
            return category
        }
        return .other
    }

    /// How busy a day was, 0 (nothing) to 4 (as busy as the busiest), for the calendar.
    nonisolated static func level(words: Int, busiest: Int) -> Int {
        guard words > 0, busiest > 0 else { return 0 }
        return min(4, max(1, Int((Double(words) / Double(busiest) * 4).rounded(.up))))
    }

    nonisolated static func dayBefore(_ key: String) -> String { shift(key, by: -1) }
    nonisolated static func dayAfter(_ key: String) -> String { shift(key, by: 1) }

    nonisolated private static func shift(_ key: String, by days: Int) -> String {
        guard let date = CostTracker.date(fromKey: key),
              let shifted = CostTracker.calendar.date(byAdding: .day, value: days, to: date) else { return key }
        return CostTracker.dayKey(shifted)
    }

    // MARK: File

    private func load() {
        guard let data = try? Data(contentsOf: file) else {
            isNew = true
            return
        }
        do {
            days = try JSONDecoder().decode(Contents.self, from: data).days.sorted { $0.date < $1.date }
        } catch {
            // Keep the unreadable file rather than saving over it.
            let aside = file.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: aside)
            Log.app.error("insights unreadable, moved aside: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Contents(days: days)).write(to: file, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            Log.app.error("insights not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
