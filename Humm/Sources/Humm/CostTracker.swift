import Foundation

/// What one request used, as OpenAI reports it in the response's `usage`: tokens for
/// gpt-4o-mini-transcribe, seconds of audio for whisper-1.
struct Usage: Equatable {
    var inputTokens = 0
    var outputTokens = 0
    var seconds: Double = 0
}

extension Usage {
    /// Reads the response's `usage` object; nil when there is none.
    init?(json: Any?) {
        guard let usage = json as? [String: Any] else { return nil }
        switch usage["type"] as? String {
        case "tokens":
            self.init(inputTokens: (usage["input_tokens"] as? NSNumber)?.intValue ?? 0,
                      outputTokens: (usage["output_tokens"] as? NSNumber)?.intValue ?? 0)
        case "duration":
            self.init(seconds: (usage["seconds"] as? NSNumber)?.doubleValue ?? 0)
        default:
            return nil
        }
    }
}

extension TranscriptionModel {
    /// When the prices below were read from OpenAI's model pages.
    static let pricesChecked = "1 Oct 2026"

    /// What a request cost in US dollars, from the usage OpenAI reported. Without it, estimated
    /// from the recording's length at OpenAI's per-minute figure.
    func cost(of usage: Usage?, recordedSeconds: Double) -> Double {
        switch self {
        case .gpt4oMiniTranscribe:
            // $1.25 per million input tokens (the audio and the spelling hint), $5.00 per million
            // output tokens.
            if let usage, usage.inputTokens + usage.outputTokens > 0 {
                return Double(usage.inputTokens) * 1.25 / 1_000_000 + Double(usage.outputTokens) * 5 / 1_000_000
            }
            return recordedSeconds / 60 * 0.003
        case .whisper1:
            // $0.006 a minute of audio.
            let seconds = usage?.seconds ?? 0
            return (seconds > 0 ? seconds : recordedSeconds) / 60 * 0.006
        }
    }
}

/// What transcription has cost, per day and model, in ~/.config/humm/costs.json (private to the
/// user). Counts and amounts only, never what was said.
@MainActor
final class CostTracker {
    nonisolated static let defaultFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/humm/costs.json")

    /// One model's requests on one day.
    struct Day: Codable, Equatable {
        /// The day on this Mac's calendar, "2026-10-01".
        let date: String
        let model: String
        var requests = 0
        /// Length of the recordings, in seconds.
        var seconds: Double = 0
        var inputTokens = 0
        var outputTokens = 0
        /// US dollars, at the prices of the day.
        var cost: Double = 0
    }

    struct Total: Equatable {
        var requests = 0
        var seconds: Double = 0
        var cost: Double = 0
    }

    enum Period { case today, yesterday, thisMonth, lastMonth, allTime }

    private struct Contents: Codable {
        var days: [Day]
    }

    let file: URL
    private(set) var days: [Day] = []

    init(file: URL = CostTracker.defaultFile) {
        self.file = file
        load()
    }

    /// Adds one request.
    func add(_ cost: Double, usage: Usage?, seconds: Double, model: TranscriptionModel, at date: Date = Date()) {
        let day = Self.dayKey(date)
        let index: Int
        if let found = days.firstIndex(where: { $0.date == day && $0.model == model.rawValue }) {
            index = found
        } else {
            days.append(Day(date: day, model: model.rawValue))
            index = days.count - 1
        }
        days[index].requests += 1
        days[index].seconds += seconds
        days[index].inputTokens += usage?.inputTokens ?? 0
        days[index].outputTokens += usage?.outputTokens ?? 0
        days[index].cost += cost
        save()
    }

    func total(_ period: Period, now: Date = Date()) -> Total {
        let calendar = Self.calendar
        let prefix = switch period {
        case .today: Self.dayKey(now)
        case .yesterday: Self.dayKey(calendar.date(byAdding: .day, value: -1, to: now) ?? now)
        case .thisMonth: String(Self.dayKey(now).prefix(7))
        case .lastMonth: String(Self.dayKey(calendar.date(byAdding: .month, value: -1, to: now) ?? now).prefix(7))
        case .allTime: ""
        }
        return days.filter { $0.date.hasPrefix(prefix) }.reduce(into: Total()) { total, day in
            total.requests += day.requests
            total.seconds += day.seconds
            total.cost += day.cost
        }
    }

    /// The first day with a cost.
    var firstDay: Date? {
        days.map(\.date).min().flatMap(Self.date(fromKey:))
    }

    // MARK: Words

    /// "$0.41", with more digits for small amounts ("$0.0042") so they don't read as nothing.
    nonisolated static func money(_ dollars: Double) -> String {
        guard dollars > 0, dollars < 0.1 else { return "$" + String(format: "%.2f", dollars) }
        // Two significant figures, at least two decimals.
        var text = String(format: "%.\(max(2, 1 - Int(floor(log10(dollars)))))f", dollars)
        while text.hasSuffix("0"), let point = text.firstIndex(of: "."), text.distance(from: point, to: text.endIndex) > 3 {
            text.removeLast()
        }
        return "$" + text
    }

    /// "45 s", "4 min", "1 h 12 min".
    nonisolated static func duration(_ seconds: Double) -> String {
        if seconds < 59.5 { return "\(Int(seconds.rounded())) s" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// "$0.41 · 213 dictations, 1 h 12 min".
    nonisolated static func describe(_ total: Total) -> String {
        guard total.requests > 0 else { return money(0) }
        return "\(money(total.cost)) · \(total.requests) dictation\(total.requests == 1 ? "" : "s"), \(duration(total.seconds))"
    }

    // MARK: File

    /// Gregorian, in this Mac's time zone, so "today" is the user's today. Insights counts days the same way.
    nonisolated static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    nonisolated static func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The start of the day a key names.
    nonisolated static func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        do {
            days = try JSONDecoder().decode(Contents.self, from: data).days
        } catch {
            // Keep the unreadable file rather than saving over it.
            let aside = file.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: aside)
            Log.app.error("costs unreadable, moved aside: \(error.localizedDescription, privacy: .public)")
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
            Log.app.error("costs not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
