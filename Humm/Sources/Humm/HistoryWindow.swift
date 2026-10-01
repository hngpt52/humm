import AppKit
import SwiftUI

/// The History window: every kept transcript, newest first and grouped by day, with search, Copy
/// on each one, and Delete in its context menu.
@MainActor
final class HistoryWindow {
    var onCopy: (Transcript) -> Void = { _ in }

    private let history: TranscriptHistory
    private var window: NSWindow?

    init(history: TranscriptHistory) {
        self.history = history
    }

    /// `activate` brings Humm forward so the search field takes typing (Humm has no Dock icon, so
    /// it must ask). Developer previews pass false and a screen, to leave the user's focus alone.
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
        let view = HistoryView(history: history, onCopy: { [weak self] in self?.onCopy($0) })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Humm History"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("HummHistory")
        return window
    }
}

private struct HistoryView: View {
    let history: TranscriptHistory
    let onCopy: (Transcript) -> Void
    @State private var query = ""
    @State private var copied: Transcript.ID?

    var body: some View {
        let entries = history.matching(query)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search transcripts", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()
            if entries.isEmpty {
                ContentUnavailableView(history.entries.isEmpty ? "No transcripts yet" : "No matches",
                                       systemImage: history.entries.isEmpty ? "waveform" : "magnifyingglass",
                                       description: Text(history.entries.isEmpty ? "What you dictate appears here." : "Nothing contains \u{201C}\(query)\u{201D}."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Self.days(entries), id: \.start) { day in
                        Section(day.title) {
                            ForEach(day.entries) { transcript in
                                row(transcript)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .tint(.primary)  // monochrome, like the pill
    }

    private func row(_ transcript: Transcript) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transcript.text)
                    .textSelection(.enabled)
                    .lineLimit(8)
                Text(Self.details(transcript))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { copy(transcript) } label: {
                Label(copied == transcript.id ? "Copied" : "Copy", systemImage: copied == transcript.id ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
        .contextMenu {
            Button("Copy") { copy(transcript) }
            Button("Delete", role: .destructive) { history.remove(transcript.id) }
        }
    }

    private func copy(_ transcript: Transcript) {
        onCopy(transcript)
        copied = transcript.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if copied == transcript.id { copied = nil }
        }
    }

    /// "14:02 · Google Chrome · 12 s · $0.0004", noting when it was not pasted.
    private static func details(_ transcript: Transcript) -> String {
        var parts = [transcript.date.formatted(date: .omitted, time: .shortened)]
        switch transcript.outcome {
        case .pasted: if let app = transcript.app { parts.append(app) }
        case .offered: parts.append("no text box selected" + (transcript.app.map { " in \($0)" } ?? ""))
        case .copied: parts.append("copied")
        }
        parts.append("\(max(1, Int(transcript.seconds.rounded()))) s")
        if let cost = transcript.cost { parts.append(CostTracker.money(cost)) }
        return parts.joined(separator: " · ")
    }

    private struct Day {
        let start: Date
        let title: String
        let entries: [Transcript]
    }

    /// Consecutive transcripts from the same day (entries are newest first).
    private static func days(_ entries: [Transcript]) -> [Day] {
        let calendar = Calendar.current
        var days: [Day] = []
        var current: [Transcript] = []
        var start: Date?
        func close() {
            guard let start, !current.isEmpty else { return }
            days.append(Day(start: start, title: title(for: start, calendar: calendar), entries: current))
        }
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if day != start {
                close()
                start = day
                current = []
            }
            current.append(entry)
        }
        close()
        return days
    }

    private static func title(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
