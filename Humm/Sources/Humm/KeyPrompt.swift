import AppKit

/// Asks for the OpenAI API key and saves it (see APIKeyStore): on first launch without one, and
/// from Add API Key… in the menu, so an app installed from the disk image needs no terminal.
@MainActor
enum KeyPrompt {
    /// True when a key was saved. Developer previews pass `activate: false` to leave focus alone.
    @discardableResult
    static func run(activate: Bool = true) -> Bool {
        let alert = NSAlert()
        let hasKey = APIKeyStore.locate() != nil
        alert.messageText = hasKey ? "Change your OpenAI API key" : "Add your OpenAI API key"
        let explanation = "Humm sends your recordings to OpenAI with your own key. The key stays on this Mac, readable only by you."
        alert.informativeText = explanation
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "sk-…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Get a Key…")
        alert.window.initialFirstResponder = field
        if activate { NSApp.activate() }
        while true {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard APIKeyStore.isPlausible(key) else {
                    alert.informativeText = "That doesn't look like an OpenAI API key: they start with \u{201C}sk-\u{201D}. " + explanation
                    continue
                }
                do {
                    try APIKeyStore.save(key)
                    Log.app.notice("api key saved")
                    return true
                } catch {
                    alert.informativeText = "The key could not be saved: \(error.localizedDescription)"
                }
            case .alertThirdButtonReturn:
                // The dialog stays up for the key to be pasted.
                NSWorkspace.shared.open(URL(string: "https://platform.openai.com/api-keys")!)
            default:
                return false
            }
        }
    }
}
