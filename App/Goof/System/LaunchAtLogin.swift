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
            return "没能设置开机启动（\(error.localizedDescription)）。把 Goof 拖进「应用程序」文件夹后再试一次"
        }
        if enabled, service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return "请在「系统设置 › 通用 › 登录项」里允许 Goof"
        }
        return nil
    }
}
