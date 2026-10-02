import AppKit
import SwiftUI

/// The Insights window: how fast you speak, how much you have dictated, what Humm fixed, where
/// you dictate and how often (see Insights), with the cost so far (see CostTracker).
@MainActor
final class InsightsWindow {
    private let insights: Insights
    private let costs: CostTracker
    private var window: NSWindow?

    init(insights: Insights, costs: CostTracker) {
        self.insights = insights
        self.costs = costs
    }

    /// As HistoryWindow: developer previews pass false and a screen, to leave the user's focus alone.
    func show(activate: Bool = true, on screen: NSScreen? = nil) {
        let window = window ?? makeWindow()
        self.window = window
        if let screen {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2, y: visible.midY - window.frame.height / 2))
        }
        if activate {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Humm Insights"
        window.contentView = NSHostingView(rootView: InsightsView(insights: insights, costs: costs))
        window.isReleasedWhenClosed = false
        window.center()
        // Previews leave the saved size and place alone.
        if !CommandLine.arguments.contains(where: { $0.hasPrefix("--preview") }) { window.setFrameAutosaveName("HummInsights") }
        return window
    }
}

private struct InsightsView: View {
    let insights: Insights
    let costs: CostTracker

    /// Weeks shown in the calendar, the current one last.
    private static let weeks = 17

    var body: some View {
        Group {
            if insights.days.isEmpty {
                ContentUnavailableView("No dictations yet", systemImage: "waveform",
                                       description: Text("Your insights fill in as you dictate."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            speed
                            fixes
                            words
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 14) {
                            apps
                            streak
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        footer
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .tint(.primary)  // monochrome, like the pill
    }

    // MARK: Cards

    private var speed: some View {
        let all = insights.summary(.allTime)
        return card {
            big(all.wordsPerMinute.map { "\(Int($0.rounded()))" } ?? "0")
            label("Words per minute")
            Divider()
            if let pace = all.wordsPerMinute {
                line(String(format: "%.1f× typing at %.0f wpm", pace / Insights.typingSpeed, Insights.typingSpeed))
            }
            line("Over recording time, pauses included.")
        }
    }

    private var fixes: some View {
        let all = insights.summary(.allTime)
        return card {
            big(all.fixes.formatted())
            label("Fixes by Humm")
            Divider()
            line(Self.count(all.dictionaryFixes, "dictionary fix", "dictionary fixes"))
            line(Self.count(all.spellingFixes, "British spelling", "British spellings"))
            line(Self.count(all.snippets, "snippet typed", "snippets typed"))
            line(Self.count(all.wordsLearned, "word learned", "words learned"))
        }
    }

    private var words: some View {
        let all = insights.summary(.allTime)
        let month = insights.summary(.thisMonth), lastMonth = insights.summary(.lastMonthSoFar)
        return card {
            big(all.words.formatted())
            label("Words dictated")
            Divider()
            line("\(month.words.formatted()) this month" + Self.change(month.words, from: lastMonth.words))
            line(Self.count(all.dictations, "dictation", "dictations") + ", \(CostTracker.duration(all.seconds)) speaking")
            line("About \(CostTracker.duration(all.minutesSaved * 60)) saved over typing")
        }
    }

    private var apps: some View {
        let kinds = insights.categories()
        let apps = insights.apps()
        let total = max(1, kinds.map(\.dictations).reduce(0, +))
        return card {
            HStack(alignment: .firstTextBaseline) {
                Text("Where you dictate").font(.title3.weight(.semibold))
                Spacer()
                label(Self.count(apps.count, "app", "apps"))
            }
            ForEach(kinds, id: \.category) { kind in
                bar(kind.category.rawValue, kind.dictations, of: total)
            }
            Divider()
            line("Most used: " + apps.prefix(4).map(\.name).joined(separator: ", "))
                .lineLimit(2)
        }
    }

    private var streak: some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.count(insights.currentStreak(), "day streak", "day streak")).font(.title3.weight(.semibold))
                Spacer()
                label("Longest " + Self.count(insights.longestStreak(), "day", "days"))
            }
            activity
            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.caption).foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in cell(level, today: false) }
                Text("More").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        var parts: [String] = []
        if let first = insights.firstDay { parts.append("Since \(first.formatted(.dateTime.day().month(.wide).year()))") }
        let spent = costs.total(.allTime).cost
        if spent > 0 {
            // Words from the days with a cost, so days before costs were kept don't dilute it.
            let costedDays = Set(costs.days.map(\.date))
            let costedWords = insights.days.filter { costedDays.contains($0.date) }.map(\.words).reduce(0, +)
            parts.append("\(CostTracker.money(spent)) spent" + (costedWords > 0 ? ", \(CostTracker.money(spent / Double(costedWords) * 1000)) per 1,000 words" : ""))
        }
        parts.append("Counts only: nothing you said is kept here")
        return Text(parts.joined(separator: "  ·  ")).font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Calendar

    /// A column a week, Monday at the top, this week last; today outlined.
    private var activity: some View {
        let calendar = CostTracker.calendar
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)  // Sunday 1 ... Saturday 7
        let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: today)!
        let start = calendar.date(byAdding: .day, value: -7 * (Self.weeks - 1), to: monday)!
        let columns: [[Date]] = (0..<Self.weeks).map { week in
            (0..<7).map { calendar.date(byAdding: .day, value: week * 7 + $0, to: start)! }
        }
        let busiest = columns.joined().map { insights.words(on: CostTracker.dayKey($0)) }.max() ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Color.clear.frame(width: 26, height: 12)
                ForEach(columns.indices, id: \.self) { index in
                    let first = columns[index][0]
                    let isNewMonth = index == 0 || calendar.component(.month, from: first) != calendar.component(.month, from: columns[index - 1][0])
                    Text(isNewMonth ? first.formatted(.dateTime.month(.abbreviated)) : "")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(width: 12, alignment: .leading)
                }
            }
            HStack(alignment: .top, spacing: 3) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(["Mon", "", "Wed", "", "Fri", "", ""][row]).font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 26, height: 12, alignment: .leading)
                    }
                }
                ForEach(columns.indices, id: \.self) { index in
                    VStack(spacing: 3) {
                        ForEach(columns[index], id: \.self) { day in
                            if day > today {
                                Color.clear.frame(width: 12, height: 12)
                            } else {
                                cell(Insights.level(words: insights.words(on: CostTracker.dayKey(day)), busiest: busiest), today: day == today)
                                    .help("\(day.formatted(.dateTime.weekday(.wide).day().month(.wide))): "
                                          + Self.count(insights.words(on: CostTracker.dayKey(day)), "word", "words"))
                            }
                        }
                    }
                }
            }
        }
    }

    private func cell(_ level: Int, today: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.primary.opacity([0.07, 0.25, 0.45, 0.7, 0.95][level]))
            .frame(width: 12, height: 12)
            .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(Color.primary.opacity(today ? 0.9 : 0), lineWidth: 1.5)
                .padding(-2))
    }

    // MARK: Pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func big(_ text: String) -> some View {
        Text(text).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
    }

    private func line(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }

    private func bar(_ name: String, _ count: Int, of total: Int) -> some View {
        let share = Double(count) / Double(total)
        return HStack(spacing: 10) {
            Text(name).font(.callout).frame(width: 128, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Color.primary.opacity(0.75)).frame(width: count > 0 ? max(6, geometry.size.width * share) : 0)
                }
            }
            .frame(height: 8)
            Text("\(Int((share * 100).rounded()))%").font(.callout).monospacedDigit().frame(width: 38, alignment: .trailing)
            Text(count.formatted()).font(.callout).monospacedDigit().foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
        }
    }

    private static func count(_ value: Int, _ one: String, _ many: String) -> String {
        "\(value.formatted()) \(value == 1 ? one : many)"
    }

    /// " (up 12% on the same days last month)", or nothing when those days had none.
    private static func change(_ now: Int, from before: Int) -> String {
        guard before > 0 else { return "" }
        let percent = Int((Double(now - before) / Double(before) * 100).rounded())
        return percent == 0 ? " (same as the same days last month)" : " (\(percent > 0 ? "up" : "down") \(abs(percent))% on the same days last month)"
    }
}
