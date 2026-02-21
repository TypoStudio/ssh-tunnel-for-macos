import SwiftUI

@main
struct SSHTunnelApp: App {
    @State private var store = ConfigStore()
    @State private var status = TunnelStatus()
    @State private var processManager: SSHProcessManager
    @State private var pendingImport: SSHTunnelConfig?
    @State private var settings = AppSettings()
    @Environment(\.openWindow) private var openWindow

    init() {
        let s = TunnelStatus()
        _status = State(initialValue: s)
        _processManager = State(initialValue: SSHProcessManager(status: s))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store, processManager: processManager, status: status, settings: settings)
                .onAppear {
                    autoConnectOnLaunch()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openManagerWindow)) { _ in
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
        } label: {
            Image("MenuBarIcon")
                .onAppear {
                    // label onAppear fires once at app launch
                    if settings.openManagerOnLaunch {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            openWindow(id: "main")
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                    if settings.autoCheckForUpdates {
                        Task {
                            if let info = await UpdateService.checkForUpdate() {
                                NSApp.activate(ignoringOtherApps: true)
                                showUpdateAlert(info: info)
                            }
                        }
                    }
                }
        }

        Settings {
            SettingsView(settings: settings)
        }

        Window(String(localized: "SSH Tunnel Manager"), id: "main") {
            TunnelListView(store: store, processManager: processManager, status: status)
                .onOpenURL { url in
                    handleURL(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    processManager.disconnectOnQuit(configs: store.configs)
                }
                .sheet(item: $pendingImport) { config in
                    ImportConfirmView(config: config, store: store)
                }
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 750, height: 500)
    }

    private func autoConnectOnLaunch() {
        for config in store.configs where config.autoConnect {
            processManager.connect(config)
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "sshtunnel" else { return }
        if let config = ShareService.decode(url.absoluteString) {
            pendingImport = config
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let openManagerWindow = Notification.Name("openManagerWindow")
}

// MARK: - URL Import Confirmation

struct ImportConfirmView: View {
    let config: SSHTunnelConfig
    let store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Import Tunnel Configuration?"))
                .font(.headline)

            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(String(localized: "Name"), value: config.name.isEmpty ? "-" : config.name)
                    LabeledContent(String(localized: "Host"), value: "\(config.username)@\(config.host):\(config.port)")
                    LabeledContent(String(localized: "Tunnels"), value: "\(config.tunnels.count) rule(s)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button(String(localized: "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Import")) {
                    store.add(config)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 350)
    }
}
