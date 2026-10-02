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

    /// `Humm --selftest-format`: technical formatting, offline.
    static func formatting() -> Int32 {
        var failures = 0
        func check(_ said: String, _ written: String, _ name: String) {
            let tidied = TechnicalText.tidy(said).text
            print((tidied == written ? "PASS " : "FAIL ") + name + (tidied == written ? "" : " got: \(tidied)"))
            if tidied != written { failures += 1 }
        }
        check("There's a 1.2 gigabyte .next slash dev folder.", "There's a 1.2 GB .next/dev folder.", "a real dictation")
        check("Clear .next slash dev slash cache now.", "Clear .next/dev/cache now.", "a chain of slashes")
        check("Look in ~ slash Library first.", "Look in ~/Library first.", "a path from home")
        check("Open lib/utils.ts slash helpers please.", "Open lib/utils.ts/helpers please.", "after a path")
        check("About 500 megabytes, a 2-gigabyte file and 3 kilobytes.", "About 500 MB, a 2 GB file and 3 KB.", "sizes in words")
        check("The 2TB drive and 1.5GB of logs.", "The 2 TB drive and 1.5 GB of logs.", "a space before units")
        check("Run npm install dash dash save-dev now.", "Run npm install --save-dev now.", "flags")
        check("Delete node underscore modules and snake underscore case underscore name.", "Delete node_modules and snake_case_name.", "snake_case")
        check("We need to slash the budget by 20%.", "We need to slash the budget by 20%.", "slash as a verb")
        check("Meet me on the dot of nine. Pages 2 slash 3 are fine.", "Meet me on the dot of nine. Pages 2 slash 3 are fine.", "prose stays prose")
        check("We have 2 gigs this weekend.", "We have 2 gigs this weekend.", "a gig is not a gigabyte")
        check("End of story. Slash notes later.", "End of story. Slash notes later.", "a full stop is not a path")
        let counted = TechnicalText.tidy("There's a 1.2 gigabyte .next slash dev folder.").count
        print((counted == 2 ? "PASS " : "FAIL ") + "counts the changes" + (counted == 2 ? "" : " got: \(counted)"))
        if counted != 2 { failures += 1 }

        let words = "Ada Lovelace, Plannr."
        let mini = TechnicalText.prompt(for: .gpt4oMiniTranscribe, dictionaryHint: words, technical: true)
        let promptChecks: [(Bool, String)] = [
            (mini == TechnicalText.styleHint + " " + words, "the default model gets the style hint, then the words"),
            (TechnicalText.prompt(for: .whisper1, dictionaryHint: words, technical: true) == words, "whisper-1 gets only the words"),
            (TechnicalText.prompt(for: .gpt4oMiniTranscribe, dictionaryHint: words, technical: false) == words, "switched off: only the words"),
            (TechnicalText.prompt(for: .whisper1, dictionaryHint: nil, technical: true) == nil, "nothing to send: no prompt"),
            (Transcriber.isNoise(TechnicalText.styleHint, hint: mini), "the style hint echoed back is noise"),
            (!Transcriber.isNoise("Check the file names in lib/utils.ts.", hint: mini), "a sentence about files is speech"),
        ]
        for (ok, name) in promptChecks {
            print((ok ? "PASS " : "FAIL ") + name)
            if !ok { failures += 1 }
        }
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

    /// `Humm --selftest-costs`: usage, prices and the costs file, without the network or the interface.
    @MainActor
    static func costs() -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
            print((ok ? "PASS " : "FAIL ") + name + (ok ? "" : " " + detail()))
            if !ok { failures += 1 }
        }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-12 }

        // Usage, as OpenAI reports it.
        let tokens = Usage(json: ["type": "tokens", "input_tokens": 1000, "output_tokens": 200, "total_tokens": 1200,
                                  "input_token_details": ["audio_tokens": 900, "text_tokens": 100]])
        check(tokens == Usage(inputTokens: 1000, outputTokens: 200), "reads token usage", "\(String(describing: tokens))")
        check(Usage(json: ["type": "duration", "seconds": 27]) == Usage(seconds: 27), "reads duration usage")
        check(Usage(json: nil) == nil && Usage(json: ["type": "other"]) == nil, "no usage reported, none read")

        // Prices.
        let mini = TranscriptionModel.gpt4oMiniTranscribe, whisper = TranscriptionModel.whisper1
        check(near(mini.cost(of: tokens, recordedSeconds: 60), 0.00225), "gpt-4o-mini-transcribe: $1.25 a million tokens in, $5 out",
              "\(mini.cost(of: tokens, recordedSeconds: 60))")
        check(near(mini.cost(of: nil, recordedSeconds: 60), 0.003), "no usage: estimated at $0.003 a minute")
        check(near(whisper.cost(of: Usage(seconds: 30), recordedSeconds: 31), 0.003), "whisper-1: $0.006 a minute billed")
        check(near(whisper.cost(of: nil, recordedSeconds: 30), 0.003), "no usage: the recording's length")

        // The costs file.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("humm-costs-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
        let tracker = CostTracker(file: file)
        check(tracker.firstDay == nil && tracker.total(.allTime, now: now) == CostTracker.Total(), "starts empty")
        tracker.add(0.002, usage: tokens, seconds: 40, model: mini, at: now)
        tracker.add(0.001, usage: nil, seconds: 20, model: mini, at: now)
        tracker.add(0.003, usage: Usage(seconds: 30), seconds: 30, model: whisper, at: now)
        tracker.add(0.010, usage: nil, seconds: 200, model: mini, at: calendar.date(byAdding: .day, value: -1, to: now)!)
        tracker.add(0.020, usage: nil, seconds: 400, model: mini, at: calendar.date(byAdding: .day, value: -40, to: now)!)
        func matches(_ period: CostTracker.Period, _ requests: Int, _ seconds: Double, _ cost: Double) -> Bool {
            let total = tracker.total(period, now: now)
            return total.requests == requests && near(total.seconds, seconds) && near(total.cost, cost)
        }
        check(matches(.today, 3, 90, 0.006), "today, both models together", "\(tracker.total(.today, now: now))")
        check(matches(.yesterday, 1, 200, 0.010), "yesterday, across the month's start")
        check(matches(.thisMonth, 3, 90, 0.006), "this month")
        check(matches(.lastMonth, 1, 200, 0.010), "last month")
        check(matches(.allTime, 5, 690, 0.036), "since the start", "\(tracker.total(.allTime, now: now))")
        check(tracker.days.count == 4, "one row per day and model", "\(tracker.days.count)")
        check(tracker.days.first?.inputTokens == 1000 && tracker.days.first?.outputTokens == 200, "keeps the token counts")
        check(tracker.firstDay == calendar.date(from: DateComponents(year: 2026, month: 8, day: 22)), "remembers the first day")

        let reloaded = CostTracker(file: file)
        check(reloaded.days == tracker.days, "saved and read back")
        let permissions = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions] as? Int
        check(permissions == 0o600, "file is private (0600)")
        let saved = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        check(!saved.contains("text"), "holds numbers, never what was said")

        try? Data("{ not json".utf8).write(to: file)
        let broken = CostTracker(file: file)
        let asides = (try? FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix(file.deletingPathExtension().lastPathComponent + ".unreadable-") } ?? []
        check(broken.days.isEmpty && asides.count == 1, "an unreadable file is kept aside, not overwritten")
        asides.forEach { try? FileManager.default.removeItem(at: $0) }

        // How amounts read.
        for (dollars, expected) in [(0.0, "$0.00"), (0.41, "$0.41"), (12.5, "$12.50"), (0.0042, "$0.0042"), (0.05, "$0.05"),
                                    (0.0123, "$0.012"), (0.000_31, "$0.00031"), (0.0999, "$0.10")] {
            check(CostTracker.money(dollars) == expected, "\(expected)", "got \(CostTracker.money(dollars)) for \(dollars)")
        }
        for (seconds, expected) in [(45.0, "45 s"), (240, "4 min"), (4320, "1 h 12 min"), (7200, "2 h")] {
            check(CostTracker.duration(seconds) == expected, expected, "got \(CostTracker.duration(seconds))")
        }
        check(CostTracker.describe(CostTracker.Total(requests: 1, seconds: 12, cost: 0.0004)) == "$0.0004 · 1 dictation, 12 s", "one dictation")
        check(CostTracker.describe(CostTracker.Total()) == "$0.00", "nothing")

        print(failures == 0 ? "all passed" : "\(failures) failed")
        return failures == 0 ? 0 : 1
    }

    /// `Humm --selftest-insights`: the insights file and what is worked out from it, offline.
    @MainActor
    static func insights() -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
            print((ok ? "PASS " : "FAIL ") + name + (ok ? "" : " " + detail()))
            if !ok { failures += 1 }
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("humm-insights-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let calendar = CostTracker.calendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }

        let insights = Insights(file: file)
        check(insights.isNew && insights.days.isEmpty, "starts new and empty")
        insights.record(words: 100, seconds: 60, app: "Claude", dictionaryFixes: 2, spellingFixes: 1, snippets: 0, at: now)
        insights.record(words: 50, seconds: 30, app: "WhatsApp", dictionaryFixes: 0, spellingFixes: 3, snippets: 1, at: now)
        insights.record(words: 40, seconds: 20, app: "Claude", dictionaryFixes: 1, spellingFixes: 0, snippets: 0, at: day(-1))
        for offset in 8...12 { insights.record(words: 10, seconds: 10, app: "Mail", dictionaryFixes: 0, spellingFixes: 0, snippets: 0, at: day(-offset)) }
        insights.recordLearned(2, at: now)

        let all = insights.summary(.allTime, now: now)
        check(all.dictations == 8 && all.words == 240 && all.seconds == 160, "adds up dictations, words and time", "\(all)")
        check(all.dictionaryFixes == 3 && all.spellingFixes == 4 && all.snippets == 1 && all.fixes == 8 && all.wordsLearned == 2, "adds up fixes and words learned")
        check(abs((all.wordsPerMinute ?? 0) - 90) < 1e-9, "words per minute over recording time", "\(String(describing: all.wordsPerMinute))")
        check(abs(all.minutesSaved - (240 / 40 - 160.0 / 60)) < 1e-9, "time saved over typing at 40 wpm")
        check(insights.summary(.thisMonth, now: now).words == 190 && insights.summary(.lastMonth, now: now).words == 50, "this month and last month")
        let months = Insights(file: file.deletingLastPathComponent().appendingPathComponent("humm-months-\(UUID().uuidString).json"))
        defer { try? FileManager.default.removeItem(at: months.file) }
        for (offset, words) in [(-31, 10), (-30, 20), (-29, 40), (-1, 5)] {
            months.record(words: words, seconds: 10, app: nil, dictionaryFixes: 0, spellingFixes: 0, snippets: 0, at: day(offset))
        }
        check(months.summary(.lastMonthSoFar, now: now).words == 30 && months.summary(.lastMonth, now: now).words == 70,
              "a month in progress compares with the same days last month", "\(months.summary(.lastMonthSoFar, now: now).words)")

        check(insights.currentStreak(now: now) == 2, "current streak: today and yesterday", "\(insights.currentStreak(now: now))")
        check(insights.currentStreak(now: day(1)) == 2, "nothing yet today: the streak runs to yesterday")
        check(insights.currentStreak(now: day(2)) == 0, "a day missed ends it")
        check(insights.longestStreak() == 5, "longest streak", "\(insights.longestStreak())")
        insights.recordLearned(-5, at: now)
        check(insights.summary(.allTime).wordsLearned == 0, "undone learning never goes below nothing")

        let apps = insights.apps()
        check(apps.map(\.name) == ["Claude", "Mail", "WhatsApp"] && apps[0].use.dictations == 2 && apps[0].use.words == 140, "apps, most words first, ties by name", "\(apps)")
        let kinds = Dictionary(uniqueKeysWithValues: insights.categories().map { ($0.category, $0.dictations) })
        check(kinds[.aiPrompts] == 2 && kinds[.personalMessages] == 1 && kinds[.emails] == 5 && kinds[.documents] == 0, "dictations per kind of app", "\(kinds)")
        let named: [(String, Insights.Category)] = [("Microsoft Outlook", .emails), ("Microsoft Word", .documents), ("Slack", .workMessages),
                                                    ("Microsoft Teams", .workMessages), ("Messages", .personalMessages), ("ChatGPT", .aiPrompts),
                                                    ("Google Chrome", .other), ("Terminal", .other), ("Notes", .documents)]
        for (app, kind) in named { check(Insights.category(of: app) == kind, "\(app) is \(kind.rawValue)") }

        check(Insights.wordCount("Hello, world! It's 3 o'clock.") == 5 && Insights.wordCount("  -  ") == 0, "counts words")
        check(Insights.level(words: 0, busiest: 100) == 0 && Insights.level(words: 1, busiest: 100) == 1
              && Insights.level(words: 50, busiest: 100) == 2 && Insights.level(words: 100, busiest: 100) == 4, "calendar levels")

        let reloaded = Insights(file: file)
        check(!reloaded.isNew && reloaded.days == insights.days, "saved and read back")
        let permissions = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions] as? Int
        check(permissions == 0o600, "file is private (0600)")

        let seeded = Insights(file: file.deletingLastPathComponent().appendingPathComponent("humm-seeded-\(UUID().uuidString).json"))
        defer { try? FileManager.default.removeItem(at: seeded.file) }
        var newer = Transcript(text: "Four words right here.", app: "Claude", outcome: .pasted, seconds: 2, model: "gpt-4o-mini-transcribe")
        newer.date = now
        var older = Transcript(text: "One two three.", app: "Notes", outcome: .pasted, seconds: 3, model: "gpt-4o-mini-transcribe")
        older.date = day(-1)
        seeded.seed(from: [newer, older])
        check(seeded.days.count == 2 && seeded.summary(.allTime).words == 7 && seeded.apps().count == 2, "starts from History's transcripts")
        seeded.seed(from: [older])
        check(seeded.summary(.allTime).dictations == 2, "seeds only once")

        try? Data("{ not json".utf8).write(to: file)
        let broken = Insights(file: file)
        let asides = (try? FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix(file.deletingPathExtension().lastPathComponent + ".unreadable-") } ?? []
        check(broken.days.isEmpty && asides.count == 1, "an unreadable file is kept aside, not overwritten")
        asides.forEach { try? FileManager.default.removeItem(at: $0) }

        print(failures == 0 ? "all passed" : "\(failures) failed")
        return failures == 0 ? 0 : 1
    }

    /// `Humm --selftest-key`: saving and reading the key file, on a scratch file (never the real one).
    static func keyFile() -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            print((ok ? "PASS " : "FAIL ") + name)
            if !ok { failures += 1 }
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("humm-key-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(".env")
        let first = "sk-test-" + String(repeating: "a", count: 24), second = "sk-proj-" + String(repeating: "b", count: 24)

        check(APIKeyStore.locate(in: file) == nil, "no file, no key")
        check((try? APIKeyStore.save(first, to: file)) != nil && APIKeyStore.locate(in: file)?.key == first, "saves a key and reads it back")
        let attributes = { (path: String) in (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? Int }
        check(attributes(file.path) == 0o600 && attributes(folder.path) == 0o700, "file 0600, folder 0700")

        try? Data("# notes\nexport OPENAI_API_KEY=\"\(first)\"\nOTHER=1\n".utf8).write(to: file)
        try? APIKeyStore.save(second, to: file)
        let saved = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        check(APIKeyStore.locate(in: file)?.key == second, "replaces the key")
        check(saved.contains("# notes") && saved.contains("OTHER=1") && !saved.contains(first), "keeps the other lines, drops the old key")

        check(APIKeyStore.isPlausible(second), "an OpenAI key looks like one")
        check(!APIKeyStore.isPlausible("hello") && !APIKeyStore.isPlausible("sk-short") && !APIKeyStore.isPlausible("sk-proj-has a space in it ok"),
              "other text does not")
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
        // `--endpoint <url>`: a local stand-in for OpenAI, sent a dummy key, never the real one.
        var stubbed = false
        if let index = positional.firstIndex(of: "--endpoint"), index + 1 < positional.count, let url = URL(string: positional[index + 1]) {
            Transcriber.endpoint = url
            stubbed = true
            positional.removeSubrange(index...(index + 1))
        }
        guard let path = positional.first else {
            print("usage: Humm --selftest <audio-file> [runs] [--prompt <text>] [--endpoint <url>]")
            return 2
        }
        let runs = positional.count > 1 ? max(1, Int(positional[1]) ?? 3) : 3
        let found: (key: String, file: URL)
        if stubbed {
            found = ("sk-stub-not-a-real-key-000000", URL(fileURLWithPath: "/dev/null"))
            print("endpoint: \(Transcriber.endpoint.absoluteString) (dummy key)")
        } else if let located = APIKeyStore.locate() {
            found = located
            print("key source: \(found.file.path)")
        } else {
            print("FAIL: no OPENAI_API_KEY found in any .env Humm checks")
            return 1
        }
        if let prompt { print("prompt: \"\(prompt)\"") }
        let file = URL(fileURLWithPath: path)
        var failures = 0
        for model in TranscriptionModel.allCases {
            for run in 1...runs {
                let started = Date()
                do {
                    let result = try await Transcriber.transcribe(fileURL: file, model: model, apiKey: found.key, prompt: prompt)
                    let usage = result.usage.map { $0.seconds > 0 ? "\($0.seconds) s billed" : "\($0.inputTokens) tokens in, \($0.outputTokens) out" }
                    let cost = CostTracker.money(model.cost(of: result.usage, recordedSeconds: 0))
                    print("\(model.rawValue) run \(run): OK \(Int(Date().timeIntervalSince(started) * 1000)) ms, \(cost) (\(usage ?? "no usage reported"))  \"\(result.text)\"")
                } catch {
                    failures += 1
                    print("\(model.rawValue) run \(run): FAIL \(error.localizedDescription)")
                }
            }
        }
        return failures == 0 ? 0 : 1
    }
}
