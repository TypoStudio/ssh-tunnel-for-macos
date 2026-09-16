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
                    // 메뉴 항목은 NSMenuItem으로 변환되어 HStack 레이아웃이 버려진다.
                    // 제목은 한 줄로 합치고, 아이콘은 titleAndIcon으로 명시해야 표시된다.
                    Label {
                        Text(config.name.isEmpty ? config.host : config.name)
                    } icon: {
                        statusDot(state)
                    }
                }
                .labelStyle(.titleAndIcon)
            }
        }

        Divider()

        Button(String(localized: "Open Manager...")) {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("m")

        Divider()

        Button(String(localized: "Reconnect All")) {
            processManager.reconnectAll()
        }
        .disabled(!store.configs.contains { status.state(for: $0.id).isActive })

        Button(String(localized: "Disconnect All")) {
            processManager.disconnectAll()
        }
        .disabled(!store.configs.contains { status.state(for: $0.id).isActive })

        Divider()

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

    /// SF Symbol은 메뉴에서 template로 그려져 색이 무시되므로, 상태 점은 직접 그린 이미지를 쓴다.
    private func statusDot(_ state: ConnectionState) -> some View {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(state.color).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return Image(nsImage: image).renderingMode(.original)
    }

    func openManagerIfNeeded() {
        if settings.openManagerOnLaunch {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
