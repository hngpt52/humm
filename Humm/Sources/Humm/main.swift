import AppKit

// `Humm --selftest <audio-file> [runs]` checks the transcription path without any UI.
if let index = CommandLine.arguments.firstIndex(of: "--selftest") {
    let arguments = Array(CommandLine.arguments.dropFirst(index + 1))
    Task {
        exit(await SelfTest.run(arguments: arguments))
    }
    dispatchMain()
}

if CommandLine.arguments.contains("--selftest-spelling") {
    exit(SelfTest.spelling())
}
if CommandLine.arguments.contains("--selftest-snippets") {
    exit(MainActor.assumeIsolated { SelfTest.snippets() })
}
if CommandLine.arguments.contains("--selftest-history") {
    exit(MainActor.assumeIsolated { SelfTest.history() })
}

// Dictionary checks (see DictionaryTests).
if let index = CommandLine.arguments.firstIndex(of: "--selftest-dictionary") {
    let arguments = Array(CommandLine.arguments.dropFirst(index + 1))
    exit(MainActor.assumeIsolated { DictionaryTests.run(arguments: arguments) })
}
if let index = CommandLine.arguments.firstIndex(of: "--selftest-corrections"), index + 1 < CommandLine.arguments.count {
    let file = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    Task { @MainActor in
        exit(await DictionaryTests.runInTextEdit(dictionaryFile: file))
    }
    dispatchMain()
}
if let index = CommandLine.arguments.firstIndex(of: "--probe-focus") {
    let seconds = index + 1 < CommandLine.arguments.count ? Double(CommandLine.arguments[index + 1]) ?? 8 : 8
    Task { @MainActor in
        exit(await SelfTest.probeFocus(seconds: seconds))
    }
    dispatchMain()
}
if let index = CommandLine.arguments.firstIndex(of: "--selftest-paste"), index + 1 < CommandLine.arguments.count {
    let file = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    Task { @MainActor in
        exit(await DictionaryTests.runPasteInTextEdit(dictionaryFile: file))
    }
    dispatchMain()
}

// Top-level code runs on the main thread; AppKit setup must be main-actor isolated.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()  // NSApplication holds its delegate weakly; this keeps it alive.
    app.delegate = delegate
    app.run()
}
