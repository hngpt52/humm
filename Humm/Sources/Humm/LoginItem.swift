import ServiceManagement

/// "Open at Login", through the system's login items.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Turns the login item on or off. Returns a message for the user when something needs
    /// their attention, nil when it simply worked.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return "Open at Login failed: \(error.localizedDescription)"
        }
        if enabled && needsApproval {
            SMAppService.openSystemSettingsLoginItems()
            return "Allow Humm in System Settings → General → Login Items."
        }
        return nil
    }
}
