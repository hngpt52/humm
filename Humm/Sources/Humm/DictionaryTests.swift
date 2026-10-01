import AppKit
import ApplicationServices

/// Developer checks for the dictionary, run from the command line:
/// - `Humm --selftest-dictionary [silent-clip loud-clip]`: correction finding, the dictionary
///   file, replacements and the noise filter, without the network or other apps.
/// - `Humm --selftest-corrections <dictionary-file>`: the Accessibility path end to end against
///   a TextEdit document titled humm-learn-test.
/// - `Humm --selftest-paste <dictionary-file>`: the same with a real ⌘V into that document, found
///   as the focused field, so it must be in front.
/// Launch the last two through `open` so the app's own Accessibility permission applies.
@MainActor
enum DictionaryTests {
    /// Stands in for the spelling dictionary, so results do not depend on the Mac's settings.
    private static let ordinaryWords: Set<String> = [
        "a", "about", "and", "ask", "base", "before", "dashboard", "deploy", "excellent", "fix", "flow",
        "figure", "first", "great", "hello", "is", "it", "keys", "launch", "live", "notes", "open", "orbit",
        "plan", "planner", "push", "restart", "runner", "same", "super", "the", "their", "there", "to", "today", "uses",
        "lens", "ready", "world", "wrold", "please", "big", "planning", "fixes", "superb", "bass", "now",
    ]
    private static func isKnown(_ word: String) -> Bool { ordinaryWords.contains(word.lowercased()) }

    private static var failures = 0

    private static func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if ok {
            print("PASS \(name)")
        } else {
            failures += 1
            print("FAIL \(name) \(detail())")
        }
    }

    // MARK: Offline checks

    static func run(arguments: [String]) -> Int32 {
        failures = 0
        correctionCases()
        dictionaryCases()
        noiseCases()
        if arguments.count >= 2 {
            let silent = Recorder.peakLoudness(of: URL(fileURLWithPath: arguments[0])) ?? 0
            let loud = Recorder.peakLoudness(of: URL(fileURLWithPath: arguments[1])) ?? -160
            check(silent < -55, "silent clip is below the silence level", "(\(silent) dBFS)")
            check(loud > -40, "spoken clip is well above it", "(\(loud) dBFS)")
        }
        let checker = NSSpellChecker.shared
        let known = { (word: String) in checker.checkSpelling(of: word, startingAt: 0).location == NSNotFound }
        check(known("planner") && !known("Plannr") && !known("Supabase"), "system spelling dictionary tells words from names")
        print(failures == 0 ? "all passed" : "\(failures) failed")
        return failures == 0 ? 0 : 1
    }

    private static func find(_ pasted: String, _ edited: String, before: String = "", after: String = "") -> Corrections.Result {
        Corrections.find(pasted: pasted, before: before, after: after, edited: edited, isKnownWord: isKnown)
    }

    private static func pairs(_ result: Corrections.Result) -> [String] {
        result.candidates.map { "\($0.from) -> \($0.to)\($0.isTerm ? "" : " (not a term)")\($0.fromIsCommonWord ? " (common)" : "")" }
    }

    private static func correctionCases() {
        var result = find("Push the planner fix before the launch.", "Push the Plannr fix before the launch.")
        check(pairs(result) == ["planner -> Plannr (common)"], "single word", "\(pairs(result))")

        result = find("Deploy it to super base today.", "Deploy it to Supabase today.")
        check(pairs(result) == ["super base -> Supabase"], "two words to one", "\(pairs(result))")

        result = find("Claro lens is ready.", "Klaro Lens is ready.")
        check(pairs(result) == ["Claro lens -> Klaro Lens"], "changed capitals join the correction next to them", "\(pairs(result))")

        result = find("It is their plan.", "It is there plan.")
        check(pairs(result) == ["their -> there (not a term) (common)"], "grammar fix is not a term", "\(pairs(result))")

        result = find("The launch is great.", "The launch is excellent.")
        check(result.found && result.candidates.isEmpty, "a different word is not a correction", "\(pairs(result))")

        result = find("Please push the planner fix to super base before the big launch today.",
                      "Please push the planning fixes to superb bass before the big launch now.")
        check(result.found && result.candidates.isEmpty, "a rewrite teaches nothing", "\(pairs(result))")

        result = find("Push the planner fix.", "")
        check(!result.found, "cleared field: pasted text gone")

        result = find("Planner.", "P.")
        check(result.found, "a one-word paste being retyped is still there")
        result = find("Planner.", "Plannr.")
        check(pairs(result) == ["Planner -> Plannr (common)"], "a one-word paste corrected", "\(pairs(result))")

        result = find("Open figure", "Open Figma and share the launch plan.")
        check(pairs(result) == ["figure -> Figma (common)"], "correction followed by new typing", "\(pairs(result))")

        result = find("Push the planner fix.", "Push the plann fix.")
        check(result.candidates.isEmpty, "half-deleted word is not learned", "\(pairs(result))")

        result = find("Push the fix.", "Hello world. Push the fix.", before: "Hello wrold. ")
        check(result.found && result.candidates.isEmpty, "edits outside the paste are ignored", "\(pairs(result))")

        result = find("Restart the Github runner.", "Restart the GitHub runner.")
        check(pairs(result) == ["Github -> GitHub"], "capitals inside a word", "\(pairs(result))")

        result = find("orbit is live.", "Orbit is live.")
        check(pairs(result) == ["orbit -> Orbit (not a term) (common)"], "capital at a sentence start is not a term", "\(pairs(result))")

        result = find("Open the orbit dashboard.", "Open the Orbit dashboard.")
        check(pairs(result) == ["orbit -> Orbit (common)"], "capital mid-sentence is a name", "\(pairs(result))")

        result = find("It is live", "It is live.")
        check(result.candidates.isEmpty, "punctuation only", "\(pairs(result))")

        let edited = "Push the Plannr fix before the launch."
        result = find("Push the planner fix before the launch.", edited)
        let range = result.candidates.first?.range ?? NSRange(location: NSNotFound, length: 0)
        check((edited as NSString).substring(with: range) == "Plannr", "reports where the correction is", "\(range)")
    }

    private static func dictionaryCases() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("humm-dictionary-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let dictionary = UserDictionary(file: file)
        func candidate(_ from: String, _ to: String, term: Bool = true, common: Bool = false) -> Corrections.Candidate {
            Corrections.Candidate(from: from, to: to, isTerm: term, fromIsCommonWord: common, range: NSRange(location: 0, length: 0))
        }

        check(dictionary.hint() == nil, "empty dictionary sends no hint")
        check(dictionary.learn([candidate("super base", "Supabase")]) == ["Supabase"], "learns a new word")
        check(dictionary.apply(to: "push to super base now") == "push to Supabase now", "replaces the misheard words")
        check(dictionary.apply(to: "push to Super-base now") == "push to Supabase now", "matches hyphens and capitals")
        check(dictionary.apply(to: "a superbase") == "a superbase", "whole words only")

        check(dictionary.learn([candidate("planner", "Plannr", common: true)]) == ["Plannr"], "learns a word heard as a common word")
        check(dictionary.apply(to: "the planner fix") == "the planner fix", "a common word is not replaced after one correction")
        check(dictionary.hint()?.contains("Plannr") == true, "but it goes into the hint")
        _ = dictionary.learn([candidate("planner", "Plannr", common: true)])
        check(dictionary.apply(to: "the planner fix") == "the Plannr fix", "replaced after a second correction")
        check(dictionary.apply(to: "Planner's great") == "Plannr's great", "keeps what follows the word")
        check(dictionary.apply(to: "two planners") == "two planners", "leaves other words alone")

        check(dictionary.learn([candidate("Plannr", "planner", term: false, common: true)]).isEmpty, "changing it back teaches no new word")
        check(dictionary.apply(to: "the planner fix") == "the planner fix", "and stops the replacement")
        _ = dictionary.learn([candidate("planner", "Plannr", common: true)])
        check(dictionary.apply(to: "the planner fix") == "the planner fix", "and it is not learned again")

        check(dictionary.learn([candidate("their", "there", term: false, common: true)]).isEmpty, "grammar fixes are not learned")

        // Fixed twice as "Plannr", then typed in lower case the third time.
        let casing = UserDictionary(file: file.deletingLastPathComponent().appendingPathComponent("humm-casing-\(UUID().uuidString).json"))
        defer { try? FileManager.default.removeItem(at: casing.file) }
        _ = casing.learn([candidate("Planter", "Plannr", common: true)])
        _ = casing.learn([candidate("Planner", "Plannr", common: true)])
        check(casing.learn([candidate("Planner", "plannr", common: true)]) == ["Plannr"], "lower case typing keeps the word's capitals")
        check(casing.words.map(\.text) == ["Plannr"] && casing.apply(to: "the Plannr app") == "the Plannr app", "and never replaces the word itself",
              "\(casing.words.map { "\($0.text) \($0.heardAs)" })")
        check(casing.apply(to: "the planner app") == "the Plannr app", "the second fix of the same spelling turns it on")
        _ = casing.learn([candidate("Github", "GitHub")])
        _ = casing.learn([candidate("git hub", "github")])
        check(casing.words.contains { $0.text == "GitHub" }, "more capitals still win (Github to GitHub)")

        // The file on disk, as a person might edit it.
        let reloaded = UserDictionary(file: file)
        check(reloaded.words.map(\.text).sorted() == ["Plannr", "Supabase"], "saved and read back", "\(reloaded.words.map(\.text))")
        let permissions = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions] as? Int
        check(permissions == 0o600, "file is private (0600)", "\(String(describing: permissions))")

        try? Data(#"{"words": ["Ada Lovelace", {"text": "Humm", "heardAs": ["hum"]}]}"#.utf8).write(to: file)
        let edited = UserDictionary(file: file)
        check(edited.words.map(\.text) == ["Ada Lovelace", "Humm"], "reads hand-written entries")
        check(edited.apply(to: "hum is the app") == "Humm is the app", "hand-written spellings apply")

        try? Data("{ not json".utf8).write(to: file)
        let broken = UserDictionary(file: file)
        check(broken.problem != nil, "reports a broken file")
        _ = broken.learn([candidate("super base", "Supabase")])
        check((try? String(contentsOf: file, encoding: .utf8)) == "{ not json", "never saves over a broken file")
    }

    private static func noiseCases() {
        let hint = "Ada Lovelace, Humm, Plannr, Supabase, GitHub."
        check(Transcriber.isNoise("Ada Lovelace, Humm, Plannr, Supabase, GitHub.", hint: hint), "hint echoed back is noise")
        check(Transcriber.isNoise("Humm, Plannr, Supabase.", hint: hint), "part of the hint echoed back is noise")
        check(!Transcriber.isNoise("Ada Lovelace", hint: hint), "one term on its own is speech")
        check(!Transcriber.isNoise("Push the Plannr fix to Supabase.", hint: hint), "a sentence using the terms is speech")
        check(Transcriber.isNoise("you", hint: nil), "whisper-1's silence word is noise")
        check(Transcriber.isNoise("ご視聴ありがとうございました", hint: hint), "whisper-1's silence phrase is noise")
        check(Transcriber.isNoise("  ", hint: nil), "blank is noise")
        check(!Transcriber.isNoise("Thank you.", hint: nil), "a short reply is speech")
    }

    // MARK: Accessibility, against TextEdit

    static func runInTextEdit(dictionaryFile: URL) async -> Int32 {
        failures = 0
        guard Paster.isTrusted(prompt: false) else {
            print("FAIL: this build has no Accessibility permission (launch it with `open`)")
            return 1
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first,
              let area = textArea(in: AXUIElementCreateApplication(app.processIdentifier), titled: "humm-learn-test")
        else {
            print("FAIL: open a TextEdit document named humm-learn-test first")
            return 1
        }
        try? FileManager.default.removeItem(at: dictionaryFile)
        let dictionary = UserDictionary(file: dictionaryFile)
        let watcher = CorrectionWatcher()
        watcher.isKnownWord = isKnown
        var learned: [String] = []
        watcher.onCorrections = { learned += dictionary.learn($0) }

        let intro = "Notes. "
        let pasted = "Push the planner fix to super base before the launch."
        for readsRanges in [true, false] {
            let how = readsRanges ? "(ranges)" : "(whole text)"

            // 1. Correct two words, then move the caret away: learned once the edit settles.
            learned = []
            set(area, intro + pasted, caret: (intro + pasted).utf16.count)
            watcher.watch(pasted: pasted, in: area, readsRanges: readsRanges)
            try? await Task.sleep(for: .seconds(2))
            set(area, intro + "Push the Plannr fix to Supabase before the launch.", caret: 0)
            try? await Task.sleep(for: .seconds(3))
            check(learned.sorted() == ["Plannr", "Supabase"], "corrections learned after they settle \(how)", "\(learned)")

            // 2. Caret still in the corrected word: waits, then learns when watching stops.
            learned = []
            set(area, intro + "Open figure first.", caret: (intro + "Open figure first.").utf16.count)
            watcher.watch(pasted: "Open figure first.", in: area, readsRanges: readsRanges)
            try? await Task.sleep(for: .seconds(2))
            set(area, intro + "Open Figma first.", caret: (intro + "Open Figma").utf16.count)
            try? await Task.sleep(for: .seconds(3))
            check(learned.isEmpty, "waits while the caret is in the word \(how)", "\(learned)")
            watcher.finish()
            check(learned == ["Figma"], "learns when watching stops \(how)", "\(learned)")

            // 3. Correct, then clear the field soon after (a chat message sent).
            learned = []
            set(area, "Deploy on ver sell today.", caret: "Deploy on ver sell today.".utf16.count)
            watcher.watch(pasted: "Deploy on ver sell today.", in: area, readsRanges: readsRanges)
            try? await Task.sleep(for: .seconds(2))
            set(area, "Deploy on Vercel today.", caret: "Deploy on Vercel".utf16.count)
            try? await Task.sleep(for: .seconds(0.8))
            set(area, "", caret: 0)
            try? await Task.sleep(for: .seconds(1))
            check(learned == ["Vercel"], "learns before the field is cleared \(how)", "\(learned)")

            // 4. A one-word paste retyped letter by letter: still learned once it settles.
            learned = []
            set(area, "Planner.", caret: "Planner.".utf16.count)
            watcher.watch(pasted: "Planner.", in: area, readsRanges: readsRanges)
            try? await Task.sleep(for: .seconds(2))
            for step in ["P.", "Pla.", "Plann.", "Plannr."] {
                set(area, step, caret: step.utf16.count - 1)  // the caret stays after the word
                try? await Task.sleep(for: .seconds(0.4))
            }
            try? await Task.sleep(for: .seconds(3))
            check(learned.isEmpty, "not learned while it might still be typed \(how)", "\(learned)")
            try? await Task.sleep(for: .seconds(3))
            check(learned == ["Plannr"], "one-word paste retyped, learned once the typing stops \(how)", "\(learned)")

            // 5. A grammar fix teaches nothing.
            learned = []
            set(area, "It is their plan.", caret: "It is their plan.".utf16.count)
            watcher.watch(pasted: "It is their plan.", in: area, readsRanges: readsRanges)
            try? await Task.sleep(for: .seconds(2))
            set(area, "It is there plan.", caret: 0)
            try? await Task.sleep(for: .seconds(3))
            watcher.finish()
            check(learned.isEmpty, "grammar fix teaches nothing \(how)", "\(learned)")
            try? FileManager.default.removeItem(at: dictionaryFile)
            dictionary.reloadIfChanged()
        }

        // The focused-field path itself cannot be driven without taking focus, so check that the
        // field is readable the way the watcher reads it.
        check(AX.string(area, kAXRoleAttribute) == kAXTextAreaRole, "TextEdit's field is a text area")
        set(area, "", caret: 0)
        print(failures == 0 ? "all passed" : "\(failures) failed")
        return failures == 0 ? 0 : 1
    }

    /// The production path: a real ⌘V into the frontmost TextEdit document, found as the focused
    /// field, then a correction. `Humm --selftest-paste <dictionary-file>`.
    static func runPasteInTextEdit(dictionaryFile: URL) async -> Int32 {
        failures = 0
        guard Paster.isTrusted(prompt: false) else {
            print("FAIL: this build has no Accessibility permission (launch it with `open`)")
            return 1
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit",
              let app = NSWorkspace.shared.frontmostApplication,
              let area = textArea(in: AXUIElementCreateApplication(app.processIdentifier), titled: "humm-learn-test")
        else {
            print("FAIL: bring a TextEdit document named humm-learn-test to the front first")
            return 1
        }
        try? FileManager.default.removeItem(at: dictionaryFile)
        let dictionary = UserDictionary(file: dictionaryFile)
        let watcher = CorrectionWatcher()  // the real spelling dictionary
        var learned: [String] = []
        watcher.onCorrections = { learned += dictionary.learn($0) }

        set(area, "", caret: 0)
        let text = "Deploy it to super base today."
        Paster.paste(text)
        watcher.watch(pasted: text)
        try? await Task.sleep(for: .seconds(2))
        check(AX.string(area, kAXValueAttribute) == text, "⌘V pasted into the focused field")
        set(area, "Deploy it to Supabase today.", caret: 0)
        try? await Task.sleep(for: .seconds(3))
        watcher.finish()
        check(learned == ["Supabase"], "correction in the focused field learned", "\(learned)")
        check(dictionary.apply(to: "push to super base") == "push to Supabase", "and applied next time")
        set(area, "", caret: 0)
        print(failures == 0 ? "all passed" : "\(failures) failed")
        return failures == 0 ? 0 : 1
    }

    /// Stands in for a paste or the user's typing: replaces the text and puts the caret down.
    private static func set(_ area: AXUIElement, _ text: String, caret: Int) {
        AXUIElementSetAttributeValue(area, kAXValueAttribute as CFString, text as CFString)
        var range = CFRange(location: caret, length: 0)
        if let value = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(area, kAXSelectedTextRangeAttribute as CFString, value)
        }
    }

    private static func textArea(in app: AXUIElement, titled title: String) -> AXUIElement? {
        for window in AX.elements(app, kAXWindowsAttribute) where (AX.string(window, kAXTitleAttribute) ?? "").contains(title) {
            var queue = [window]
            while !queue.isEmpty {
                let element = queue.removeFirst()
                if AX.string(element, kAXRoleAttribute) == kAXTextAreaRole { return element }
                queue += AX.elements(element, kAXChildrenAttribute)
            }
        }
        return nil
    }
}
