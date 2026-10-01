import AppKit
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState?
    private var statusMenu: StatusMenu?
    private var pill: FloatingPill?
    private var historyWindow: HistoryWindow?
    private var snippetsWindow: SnippetsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState()
        let statusMenu = StatusMenu(state: state)
        let pill = FloatingPill(state: state)
        state.onChange = { [weak statusMenu, weak pill] in
            statusMenu?.refresh()
            pill?.refresh()
        }
        self.state = state
        statusMenu.onResetPill = { [weak pill] in pill?.resetPlacement() }
        let historyWindow = HistoryWindow(history: state.history)
        historyWindow.onCopy = { [weak state] transcript in state?.copyFromHistory(transcript) }
        statusMenu.onShowHistory = { [weak historyWindow] in historyWindow?.show() }
        self.historyWindow = historyWindow
        let snippetsWindow = SnippetsWindow(store: state.snippets)
        statusMenu.onShowSnippets = { [weak snippetsWindow] in snippetsWindow?.show() }
        self.snippetsWindow = snippetsWindow
        self.statusMenu = statusMenu
        self.pill = pill
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--preview"), index + 1 < arguments.count {
            state.preview(arguments[index + 1])
        }
        if let index = arguments.firstIndex(of: "--preview-rail"), index + 1 < arguments.count {
            let screen = arguments.firstIndex(of: "--preview-screen").flatMap { $0 + 1 < arguments.count ? Int(arguments[$0 + 1]) : nil }
            pill.previewRail(arguments[index + 1], screen: screen)
        }
        // `--preview-history` opens the History window without taking focus (with `--history-file`
        // for sample data, and `--preview-screen <n>` for the display).
        var previewScreen: NSScreen?
        if let index = arguments.firstIndex(of: "--preview-screen"), index + 1 < arguments.count,
           let number = Int(arguments[index + 1]), NSScreen.screens.indices.contains(number - 1) {
            previewScreen = NSScreen.screens[number - 1]
        }
        if arguments.contains("--preview-history") {
            historyWindow.show(activate: false, on: previewScreen)
        }
        // `--preview-snippets` likewise (with `--snippets-file`); `--preview-new-snippet` opens the editor.
        if arguments.contains("--preview-snippets") || arguments.contains("--preview-new-snippet") {
            snippetsWindow.show(activate: false, on: previewScreen, editing: arguments.contains("--preview-new-snippet"))
        }
        // `--open-at-login` switches the login item on, for scripted setups.
        if arguments.contains("--open-at-login") {
            state.setOpenAtLogin(true)
        }
        // Installed from the disk image there is no script to add the key, so ask for it.
        // `--preview-key-prompt` shows the prompt without taking focus.
        if arguments.contains("--preview-key-prompt") {
            Task { @MainActor in KeyPrompt.run(activate: false) }
        } else if APIKeyStore.locate() == nil, !arguments.contains(where: { $0.hasPrefix("--preview") }) {
            Task { @MainActor in KeyPrompt.run() }
        }
        Log.app.notice("launched: accessibility=\(Paster.isTrusted(prompt: false), privacy: .public) keyFound=\(APIKeyStore.locate() != nil, privacy: .public) mic=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue, privacy: .public)")
    }
}
