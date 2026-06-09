import Foundation
import ServiceManagement

@Observable
final class AppSettings {
    var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin() }
    }
    var openManagerOnLaunch: Bool {
        didSet { UserDefaults.standard.set(openManagerOnLaunch, forKey: "openManagerOnLaunch") }
    }
    var autoCheckForUpdates: Bool {
        didSet { UserDefaults.standard.set(autoCheckForUpdates, forKey: "autoCheckForUpdates") }
    }
    var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    init() {
        self.openManagerOnLaunch = UserDefaults.standard.bool(forKey: "openManagerOnLaunch")
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        if UserDefaults.standard.object(forKey: "autoCheckForUpdates") == nil {
            self.autoCheckForUpdates = true
        } else {
            self.autoCheckForUpdates = UserDefaults.standard.bool(forKey: "autoCheckForUpdates")
        }

        if UserDefaults.standard.object(forKey: "notificationsEnabled") == nil {
            self.notificationsEnabled = true
        } else {
            self.notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        }
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
            // Revert on failure
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
