import SwiftUI

struct MenuBarView: View {
    let store: ConfigStore
    let processManager: SSHProcessManager
    let status: TunnelStatus
    let settings: AppSettings

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if store.configs.isEmpty {
            Text(String(localized: "No tunnels configured"))
                .foregroundStyle(.secondary)
        } else {
            ForEach(store.configs) { config in
                let state = status.state(for: config.id)
                Button {
                    processManager.toggle(config)
                } label: {
                    HStack {
                        Image(systemName: state == .connected ? "circle.fill" : "circle")
                            .foregroundStyle(state.color)
                        Text(config.name.isEmpty ? config.host : config.name)
                        Spacer()
                        Text(state.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        Divider()

        Button(String(localized: "Open Manager...")) {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("m")

        Divider()

        Button(String(localized: "Disconnect All")) {
            processManager.disconnectAll()
        }
        .disabled(!store.configs.contains { status.state(for: $0.id).isActive })

        Button(String(localized: "Check for Updates...")) {
            Task {
                if let info = await UpdateService.checkForUpdate() {
                    NSApp.activate(ignoringOtherApps: true)
                    showUpdateAlert(info: info)
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    showUpToDateAlert()
                }
            }
        }

        SettingsLink {
            Text(String(localized: "Settings..."))
        }
        .keyboardShortcut(",")

        Button(String(localized: "Quit")) {
            processManager.disconnectAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        }
        .keyboardShortcut("q")
    }

    func openManagerIfNeeded() {
        if settings.openManagerOnLaunch {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
