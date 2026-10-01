import AppKit

/// Transcribes an audio file with each model and prints the latency of every run.
/// `--prompt <text>` sends a spelling hint with each request.
enum SelfTest {
    /// `Humm --selftest-spelling`: American to British spelling, offline.
    static func spelling() -> Int32 {
        var failures = 0
        func check(_ american: String, _ british: String, _ name: String) {
            let converted = BritishSpelling.convert(american)
            print((converted == british ? "PASS " : "FAIL ") + name + (converted == british ? "" : " got: \(converted)"))
            if converted != british { failures += 1 }
        }
        // What gpt-4o-mini-transcribe wrote for a British speaker, with or without a British prompt.
        check("I realize the color of the theater is my favorite, so let us organize a program to analyze the behavior of every traveler. We walked 12 kilometers to the town center, and I apologize for my humor. The catalog in the gray jewelry shop was canceled.",
              "I realise the colour of the theatre is my favourite, so let us organise a program to analyse the behaviour of every traveller. We walked 12 kilometres to the town centre, and I apologise for my humour. The catalogue in the grey jewellery shop was cancelled.",
              "a real transcript")
        check("Color, COLOR and color.", "Colour, COLOUR and colour.", "keeps capitals")
        check("The organization organized its organizers.", "The organisation organised its organisers.", "inflections and nouns")
        check("Analyzing the neighborhood's behavioral data.", "Analysing the neighbourhood's behavioural data.", "-yze, -or and apostrophes")
        check("Resize it to the right size before you seize the prize.", "Resize it to the right size before you seize the prize.", "keeps size, seize, prize")
        check("A humorous, laborious and glamorous program.", "A humorous, laborious and glamorous program.", "keeps words spelt the same")
        check("Check the license, practice the tire change, read the meter.", "Check the license, practice the tire change, read the meter.", "leaves meaning-dependent words")
        check("Colorado and Honorius are names.", "Colorado and Honorius are names.", "whole words only")
        print(failures == 0 ? "all passed" : "\(failures) failed")
        return failures == 0 ? 0 : 1
    }

    /// `Humm --selftest-snippets`: snippet rules and the file, without the network or the interface.
    @MainActor
    static func snippets() -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
            print((ok ? "PASS " : "FAIL ") + name + (ok ? "" : " " + detail()))
            if !ok { failures += 1 }
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("humm-snippets-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = SnippetStore(file: file)
        let link = "https://cal.example/sam/30"
        let signature = "Best,\nSam"

        check(store.save(Snippet(trigger: " ", text: "x")) == .shortTrigger, "rejects an empty phrase")
        check(store.save(Snippet(trigger: "my link", text: "  ")) == .emptyText, "rejects empty text")
        check(store.save(Snippet(trigger: "my  calendar   link", text: link)) == nil, "saves a snippet")
        check(store.snippets.first?.trigger == "my calendar link", "tidies spaces in the phrase")
        check(store.save(Snippet(trigger: "My Calendar Link", text: "other")) == .duplicate, "rejects the same phrase twice")
        store.save(Snippet(trigger: "sign off", text: signature))
        store.save(Snippet(trigger: "sign off formally", text: "Yours sincerely,\nSam Taylor"))
        store.save(Snippet(trigger: "the team note", text: "Sign off by Friday."))

        func expand(_ text: String) -> String { store.expand(text).text }
        check(expand("My calendar link.") == link, "said alone: only the snippet, no stray full stop", expand("My calendar link."))
        check(expand("Here is my calendar link, thanks.") == "Here is \(link), thanks.", "said in a sentence", expand("Here is my calendar link, thanks."))
        check(expand("MY CALENDAR-LINK") == link, "ignores case and hyphens")
        check(expand("Check my calendar linking.") == "Check my calendar linking.", "whole words only")
        check(expand("Sign off formally.") == "Yours sincerely,\nSam Taylor", "longer phrase wins")
        check(expand("Please send the team note today.") == "Please send Sign off by Friday. today.", "a snippet's text is not expanded again",
              expand("Please send the team note today."))
        check(expand("Thanks! Sign off.") == "Thanks! \(signature).", "keeps lines", expand("Thanks! Sign off."))
        check(store.expand("Nothing to see.").count == 0, "counts nothing when no phrase was said")

        let reloaded = SnippetStore(file: file)
        check(reloaded.snippets == store.snippets, "saved and read back")
        let permissions = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions] as? Int
        check(permissions == 0o600, "file is private (0600)")
        store.remove(store.snippets[0].id)
        check(store.snippets.count == 3, "deletes one")

        print(failures == 0 ? "all passed" : "\(failures) failed")
        return failures == 0 ? 0 : 1
    }

    /// `Humm --selftest-history`: the history file, without the network or the interface.
    @MainActor
    static func history() -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            print((ok ? "PASS " : "FAIL ") + name)
            if !ok { failures += 1 }
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("humm-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        func transcript(_ text: String, _ outcome: Transcript.Outcome = .pasted) -> Transcript {
            Transcript(text: text, app: "TextEdit", outcome: outcome, seconds: 3.2, model: "gpt-4o-mini-transcribe")
        }

        let history = TranscriptHistory(file: file)
        check(history.entries.isEmpty, "starts empty")
        history.add(transcript("First, about the launch."))
        history.add(transcript("Push the Plannr fix to Supabase.", .offered))
        history.add(transcript("Café opens at nine.", .copied))
        check(history.entries.map(\.text) == ["Café opens at nine.", "Push the Plannr fix to Supabase.", "First, about the launch."], "newest first")
        check(history.matching("plannr").count == 1, "search ignores case")
        check(history.matching("cafe").count == 1, "search ignores accents")
        check(history.matching("  ").count == 3, "blank search shows everything")

        let reloaded = TranscriptHistory(file: file)
        check(reloaded.entries == history.entries, "saved and read back")
        let permissions = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions] as? Int
        check(permissions == 0o600, "file is private (0600)")

        history.remove(history.entries[1].id)
        check(history.entries.map(\.outcome) == [.copied, .pasted], "deletes one")

        for index in 0..<(TranscriptHistory.limit + 5) { history.add(transcript("Note \(index)")) }
        check(history.entries.count == TranscriptHistory.limit, "keeps at most \(TranscriptHistory.limit)")
        check(history.entries.first?.text == "Note \(TranscriptHistory.limit + 4)", "drops the oldest")

        history.clear()
        check(history.entries.isEmpty && !FileManager.default.fileExists(atPath: file.path), "clear deletes the file")

        try? Data("{ not json".utf8).write(to: file)
        let broken = TranscriptHistory(file: file)
        let asides = (try? FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix(file.deletingPathExtension().lastPathComponent + ".unreadable-") } ?? []
        check(broken.entries.isEmpty && asides.count == 1, "an unreadable file is kept aside, not overwritten")
        asides.forEach { try? FileManager.default.removeItem(at: $0) }

        print(failures == 0 ? "all passed" : "\(failures) failed")
        return failures == 0 ? 0 : 1
    }

    /// `Humm --probe-focus [seconds] [--app <bundle id>]`: prints the focused element's role in the
    /// app in front (or the named one), and whether Humm would paste there or show the copy card.
    /// Never reads text. Launch with `open` so Humm's Accessibility permission applies.
    @MainActor
    static func probeFocus(seconds: Double) async -> Int32 {
        guard Paster.isTrusted(prompt: false) else {
            print("FAIL: no Accessibility permission (launch with open)")
            return 1
        }
        // As at the start of a recording: ask the app in front for its accessibility tree.
        if let front = NSWorkspace.shared.frontmostApplication {
            print("front: \(front.bundleIdentifier ?? "?")")
            AX.askForTree(pid: front.processIdentifier, name: front.bundleIdentifier ?? "?")
        }
        var target = NSWorkspace.shared.frontmostApplication
        if let index = CommandLine.arguments.firstIndex(of: "--app"), index + 1 < CommandLine.arguments.count,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[index + 1]).first {
            target = app
            AX.askForTree(pid: app.processIdentifier, name: app.bundleIdentifier ?? "?")
            print("probing \(app.bundleIdentifier ?? "?") (not in front)")
        }
        let end = Date().addingTimeInterval(seconds)
        var last = ""
        while Date() < end {
            let line: String
            if let focus = Focus.current(in: target) {
                AX.askForTree(pid: focus.pid, name: focus.app)
                line = "\(focus.app): \(focus.role)\(focus.subrole.map { "/" + $0 } ?? "") -> \(focus.takesText ? "paste" : "copy card")"
            } else {
                line = "no focused element -> copy card"
            }
            if line != last { print(line); last = line }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return 0
    }

    static func run(arguments: [String]) async -> Int32 {
        var positional = arguments
        var prompt: String?
        if let index = positional.firstIndex(of: "--prompt"), index + 1 < positional.count {
            prompt = positional[index + 1]
            positional.removeSubrange(index...(index + 1))
        }
        guard let path = positional.first else {
            print("usage: Humm --selftest <audio-file> [runs] [--prompt <text>]")
            return 2
        }
        let runs = positional.count > 1 ? max(1, Int(positional[1]) ?? 3) : 3
        guard let found = APIKeyStore.locate() else {
            print("FAIL: no OPENAI_API_KEY found in any .env Humm checks")
            return 1
        }
        print("key source: \(found.file.path)")
        if let prompt { print("prompt: \"\(prompt)\"") }
        let file = URL(fileURLWithPath: path)
        var failures = 0
        for model in TranscriptionModel.allCases {
            for run in 1...runs {
                let started = Date()
                do {
                    let text = try await Transcriber.transcribe(fileURL: file, model: model, apiKey: found.key, prompt: prompt)
                    print("\(model.rawValue) run \(run): OK \(Int(Date().timeIntervalSince(started) * 1000)) ms  \"\(text)\"")
                } catch {
                    failures += 1
                    print("\(model.rawValue) run \(run): FAIL \(error.localizedDescription)")
                }
            }
        }
        return failures == 0 ? 0 : 1
    }
}
