import AppKit

/// Menu-bar icon and menu. Plain AppKit; the menu is rebuilt each time it opens.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let state: AppState
    /// Brings the pill back to the bottom centre of the main screen.
    var onResetPill: () -> Void = {}
    var onShowHistory: () -> Void = {}
    var onShowSnippets: () -> Void = {}

    init(state: AppState) {
        self.state = state
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        refresh()
    }

    func refresh() {
        let image = NSImage(systemSymbolName: state.menuBarSymbol, accessibilityDescription: "Humm")
        image?.isTemplate = true
        item.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        Log.input.notice("menu opened")
        menu.removeAllItems()
        menu.addItem(info(state.statusText))
        if let ms = state.lastLatencyMs {
            menu.addItem(info("Last: \(ms) ms from stop to paste" + (state.lastCost.map { ", " + CostTracker.money($0) } ?? "")))
        }
        menu.addItem(.separator())

        for model in TranscriptionModel.allCases {
            let entry = action(model.label, #selector(selectModel(_:)))
            entry.representedObject = model.rawValue
            entry.state = model == state.model ? .on : .off
            menu.addItem(entry)
        }
        let british = action("British Spelling", #selector(toggleBritishSpelling))
        british.state = state.britishSpelling ? .on : .off
        menu.addItem(british)
        menu.addItem(costsItem())
        menu.addItem(.separator())

        let keys = action("Keyboard Shortcuts", #selector(toggleKeyboardShortcuts))
        keys.state = state.keyboardShortcuts ? .on : .off
        menu.addItem(keys)
        if state.keyboardShortcuts {
            menu.addItem(info("Hold ⌃ Ctrl + ⌥ Opt to talk, let go to finish."))
            menu.addItem(info("Add Space for hands-free; ⌃ Ctrl + ⌥ Opt again to finish."))
            menu.addItem(info("Esc cancels."))
        }
        menu.addItem(.separator())

        let learn = action(Paster.isTrusted(prompt: false) ? "Learn from My Corrections" : "Learn from My Corrections (needs Accessibility)",
                           #selector(toggleLearning))
        learn.state = state.learnFromCorrections ? .on : .off
        menu.addItem(learn)
        menu.addItem(dictionaryItem())
        let snippetCount = state.snippets.snippets.count
        menu.addItem(action(snippetCount == 0 ? "Snippets…" : "Snippets (\(snippetCount))…", #selector(showSnippets)))
        menu.addItem(.separator())

        let pill = action("Show Floating Pill", #selector(toggleFloatingButton))
        pill.state = state.showFloatingButton ? .on : .off
        menu.addItem(pill)
        if NSScreen.screens.count > 1 {
            let follow = action("Pill Follows Mouse Between Displays", #selector(togglePillFollowsMouse))
            follow.state = state.pillFollowsMouse ? .on : .off
            follow.isEnabled = state.showFloatingButton
            menu.addItem(follow)
        }
        let reset = action("Reset Pill Position", #selector(resetPill))
        reset.isEnabled = state.showFloatingButton
        menu.addItem(reset)
        let login = action(LoginItem.needsApproval ? "Open at Login (needs approval)" : "Open at Login",
                           #selector(toggleOpenAtLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        let sounds = action("Play Sounds", #selector(toggleSounds))
        sounds.state = state.playSounds ? .on : .off
        menu.addItem(sounds)
        menu.addItem(historyItem())
        let keep = action("Keep History", #selector(toggleKeepHistory))
        keep.state = state.keepHistory ? .on : .off
        menu.addItem(keep)
        let copy = action("Copy Last Transcript", #selector(copyLastTranscript))
        copy.isEnabled = !state.lastTranscript.isEmpty
        menu.addItem(copy)
        menu.addItem(action(APIKeyStore.locate() == nil ? "Add API Key…" : "Change API Key…", #selector(setAPIKey)))
        if !Paster.isTrusted(prompt: false) {
            menu.addItem(action("Grant Accessibility (to paste and learn)…", #selector(grantAccessibility)))
        }
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Humm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    /// History submenu: the ten latest transcripts (click to copy), then the full window.
    private func historyItem() -> NSMenuItem {
        let entries = state.history.entries
        let item = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        if entries.isEmpty {
            submenu.addItem(info(state.keepHistory ? "No transcripts yet." : "History is off."))
        } else {
            submenu.addItem(info("Click one to copy it."))
            for transcript in entries.prefix(10) {
                let entry = action(Self.menuTitle(for: transcript), #selector(copyHistoryEntry(_:)))
                entry.representedObject = transcript.id.uuidString
                entry.toolTip = transcript.text
                submenu.addItem(entry)
            }
        }
        submenu.addItem(.separator())
        submenu.addItem(action("Show All History…", #selector(showHistory)))
        let clear = action("Clear History…", #selector(clearHistory))
        clear.isEnabled = !entries.isEmpty
        submenu.addItem(clear)
        item.submenu = submenu
        return item
    }

    /// "14:02   Push the Plannr fix to…", with the day for older ones.
    private static func menuTitle(for transcript: Transcript) -> String {
        let calendar = Calendar.current
        let when = calendar.isDateInToday(transcript.date)
            ? transcript.date.formatted(date: .omitted, time: .shortened)
            : transcript.date.formatted(.dateTime.day().month(.abbreviated))
        let text = transcript.text.replacingOccurrences(of: "\n", with: " ")
        return "\(when)   " + (text.count > 60 ? String(text.prefix(59)) + "…" : text)
    }

    /// Costs submenu: what transcription has cost, from the usage OpenAI reports with each request.
    private func costsItem() -> NSMenuItem {
        let costs = state.costs
        let item = NSMenuItem(title: "Costs: \(CostTracker.money(costs.total(.thisMonth).cost)) This Month", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        if let first = costs.firstDay {
            submenu.addItem(info("Today: " + CostTracker.describe(costs.total(.today))))
            submenu.addItem(info("Yesterday: " + CostTracker.describe(costs.total(.yesterday))))
            submenu.addItem(info("This month: " + CostTracker.describe(costs.total(.thisMonth))))
            // Only once there is a last month to speak of.
            if CostTracker.dayKey(first).prefix(7) != CostTracker.dayKey(Date()).prefix(7) {
                submenu.addItem(info("Last month: " + CostTracker.describe(costs.total(.lastMonth))))
            }
            submenu.addItem(info("Since \(first.formatted(.dateTime.day().month(.wide).year())): " + CostTracker.describe(costs.total(.allTime))))
        } else {
            submenu.addItem(info("Nothing yet. Each dictation's cost is added here."))
        }
        submenu.addItem(.separator())
        submenu.addItem(info("From the usage OpenAI reports, at its prices on \(TranscriptionModel.pricesChecked)."))
        submenu.addItem(action("Open OpenAI Usage…", #selector(openOpenAIUsage)))
        item.submenu = submenu
        return item
    }

    /// Dictionary submenu: every word, each with a Remove item, and the file for hand edits.
    private func dictionaryItem() -> NSMenuItem {
        let dictionary = state.dictionary
        dictionary.reloadIfChanged()
        let words = dictionary.words.sorted { $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending }
        let item = NSMenuItem(title: words.isEmpty ? "Dictionary" : "Dictionary (\(words.count))", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        if let problem = dictionary.problem {
            submenu.addItem(info(problem))
        } else if words.isEmpty {
            submenu.addItem(info("No words yet. Fix a word after dictating and Humm learns it."))
        } else {
            submenu.addItem(info("Sent to OpenAI as spelling hints."))
        }
        for word in words {
            var title = word.heardAs.isEmpty ? word.text : "\(word.text)  ← \(word.heardAs.joined(separator: ", "))"
            // Ordinary words are only replaced after a second fix.
            if !word.pending.isEmpty { title += "  (\(word.pending.joined(separator: ", ")) after one more fix)" }
            let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let options = NSMenu()
            let remove = action("Remove \(word.text)", #selector(removeWord(_:)))
            remove.representedObject = word.text
            options.addItem(remove)
            entry.submenu = options
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        submenu.addItem(action("Edit Dictionary File…", #selector(openDictionaryFile)))
        item.submenu = submenu
        return item
    }

    private func info(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        entry.target = self
        return entry
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let model = TranscriptionModel(rawValue: raw) else { return }
        Log.input.notice("menu: model \(raw, privacy: .public)")
        state.model = model
    }

    @objc private func toggleBritishSpelling() {
        Log.input.notice("menu: british spelling")
        state.britishSpelling.toggle()
    }

    @objc private func toggleKeyboardShortcuts() {
        Log.input.notice("menu: keyboard shortcuts")
        state.keyboardShortcuts.toggle()
    }

    @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? String).flatMap(UUID.init(uuidString:)),
              let transcript = state.history.entries.first(where: { $0.id == id }) else { return }
        state.copyFromHistory(transcript)
    }

    @objc private func showSnippets() {
        Log.input.notice("menu: show snippets")
        onShowSnippets()
    }

    @objc private func showHistory() {
        Log.input.notice("menu: show history")
        onShowHistory()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        let count = state.history.entries.count
        alert.messageText = "Clear \(count == 1 ? "the transcript" : "all \(count) transcripts") from History?"
        alert.informativeText = "This deletes them from this Mac. It can't be undone."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.clearHistory()
    }

    @objc private func toggleKeepHistory() {
        Log.input.notice("menu: keep history")
        state.keepHistory.toggle()
    }

    @objc private func toggleLearning() {
        Log.input.notice("menu: learn from corrections")
        state.learnFromCorrections.toggle()
    }

    @objc private func removeWord(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        Log.input.notice("menu: remove word")
        state.removeWord(text)
    }

    @objc private func openOpenAIUsage() {
        Log.input.notice("menu: openai usage")
        NSWorkspace.shared.open(URL(string: "https://platform.openai.com/usage")!)
    }

    @objc private func openDictionaryFile() {
        // The default editor for .json: TextEdit would turn typed quotes into curly ones.
        let dictionary = state.dictionary
        dictionary.createFileIfMissing()
        NSWorkspace.shared.open(dictionary.file)
    }

    @objc private func resetPill() {
        Log.input.notice("menu: reset pill position")
        onResetPill()
    }

    @objc private func toggleFloatingButton() {
        Log.input.notice("menu: toggle floating button")
        state.showFloatingButton.toggle()
    }

    @objc private func togglePillFollowsMouse() {
        Log.input.notice("menu: pill follows mouse")
        state.pillFollowsMouse.toggle()
    }

    @objc private func toggleOpenAtLogin() {
        Log.input.notice("menu: open at login")
        state.setOpenAtLogin(!LoginItem.isEnabled)
    }

    @objc private func toggleSounds() {
        state.playSounds.toggle()
    }

    @objc private func copyLastTranscript() {
        Paster.copy(state.lastTranscript)
    }

    @objc private func setAPIKey() {
        Log.input.notice("menu: api key")
        KeyPrompt.run()
    }

    @objc private func grantAccessibility() {
        _ = Paster.isTrusted(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
