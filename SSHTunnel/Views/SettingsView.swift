import SwiftUI

enum SettingsTab: String {
    case general
    case about
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(settings: settings)
                .tabItem {
                    Label(String(localized: "General"), systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            AboutSettingsView()
                .tabItem {
                    Label(String(localized: "About"), systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 360, height: 260)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var updateStatus: UpdateCheckStatus = .idle

    var body: some View {
        Form {
            Toggle(String(localized: "Launch at Login"), isOn: $settings.launchAtLogin)
            Toggle(String(localized: "Open Manager on Launch"), isOn: $settings.openManagerOnLaunch)
            Toggle(String(localized: "Check for Updates Automatically"), isOn: $settings.autoCheckForUpdates)

            HStack {
                Button(String(localized: "Check Now")) {
                    checkNow()
                }
                .disabled(updateStatus == .checking)

                switch updateStatus {
                case .checking:
                    ProgressView()
                        .controlSize(.small)
                case .available(let version):
                    Text(String(localized: "v\(version) available"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                case .upToDate:
                    Text(String(localized: "You're up to date."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .idle:
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func checkNow() {
        updateStatus = .checking
        Task {
            if let info = await UpdateService.checkForUpdate() {
                updateStatus = .available(version: info.version)
                showUpdateAlert(info: info)
            } else {
                updateStatus = .upToDate
            }
        }
    }
}

private enum UpdateCheckStatus: Equatable {
    case idle
    case checking
    case available(version: String)
    case upToDate
}

// MARK: - About

private struct AboutSettingsView: View {
    private let bmcURL = URL(string: "https://www.buymeacoffee.com/typ0s2d10")!
    private let githubURL = URL(string: "https://github.com/TypoStudio/ssh-tunnel-for-macos")!

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text("SSH Tunnel Manager")
                        .font(.headline)
                    Text(String(localized: "Version %@", defaultValue: "Version \(appVersion)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text("Copyright (c) 2026 TypoStudio (typ0s2d10@gmail.com)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 12) {
                imageLink("GitHubMark", url: githubURL)
                imageLink("BMCButton", url: bmcURL)
            }
        }
        .padding()
    }

    private func imageLink(_ imageName: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(height: 34)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
