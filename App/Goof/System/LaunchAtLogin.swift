import ServiceManagement

/// "Open at login" through the system's Login Items (no helper app needed).
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Returns a message for the user when it did not simply work.
    static func set(_ enabled: Bool) -> String? {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            return "Couldn't turn on launch at login (\(error.localizedDescription)). Move Goof to the Applications folder and try again"
        }
        if enabled, service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return "Allow Goof in System Settings › General › Login Items"
        }
        return nil
    }
}
