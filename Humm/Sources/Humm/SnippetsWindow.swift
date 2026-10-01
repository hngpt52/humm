import AppKit
import SwiftUI

/// The Snippets window: every snippet with its phrase and text, New Snippet, and an editor sheet.
@MainActor
final class SnippetsWindow {
    private let store: SnippetStore
    private var window: NSWindow?

    init(store: SnippetStore) {
        self.store = store
    }

    /// `activate` brings Humm forward so the editor takes typing. Developer previews pass false and
    /// a screen; `editing` opens the editor on a new snippet.
    func show(activate: Bool = true, on screen: NSScreen? = nil, editing: Bool = false) {
        let window = window ?? makeWindow(editing: editing)
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

    private func makeWindow(editing: Bool) -> NSWindow {
        let view = SnippetsView(store: store, editing: editing ? Snippet(trigger: "", text: "") : nil)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Humm Snippets"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("HummSnippets")
        return window
    }
}

private struct SnippetsView: View {
    let store: SnippetStore
    @State var editing: Snippet?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("Say a phrase while dictating and Humm types its text instead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { editing = Snippet(trigger: "", text: "") } label: { Label("New Snippet", systemImage: "plus") }
            }
            .padding(12)
            Divider()
            if store.snippets.isEmpty {
                ContentUnavailableView("No snippets yet", systemImage: "text.bubble",
                                       description: Text("Say \u{201C}my calendar link\u{201D} to type the link itself, or \u{201C}sign off\u{201D} for your signature."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.snippets) { snippet in
                    row(snippet)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 440, minHeight: 320)
        .tint(.primary)  // monochrome, like the pill
        .sheet(item: $editing) { snippet in
            SnippetEditor(store: store, snippet: snippet) { editing = nil }
        }
    }

    private func row(_ snippet: Snippet) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\u{201C}\(snippet.trigger)\u{201D}").font(.headline)
                Text(snippet.text)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button { editing = snippet } label: { Label("Edit", systemImage: "pencil") }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
        .contextMenu {
            Button("Edit") { editing = snippet }
            Button("Delete", role: .destructive) { store.remove(snippet.id) }
        }
    }
}

private struct SnippetEditor: View {
    let store: SnippetStore
    @State var snippet: Snippet
    let close: () -> Void
    @State private var problem: SnippetStore.Problem?

    var body: some View {
        let isNew = !store.contains(snippet.id)
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Snippet" : "Edit Snippet").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("When I say").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. my calendar link", text: $snippet.trigger)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Humm types").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $snippet.text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                    .overlay(alignment: .topLeading) {
                        if snippet.text.isEmpty {
                            Text(verbatim: "e.g. https://cal.com/you/30min")  // verbatim: no blue link
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 120)
            }
            if let problem {
                Text(problem.message).font(.caption).foregroundStyle(.red)
            }
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        store.remove(snippet.id)
                        close()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    problem = store.save(snippet)
                    if problem == nil { close() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
