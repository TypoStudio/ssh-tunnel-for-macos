import SwiftUI
import AppKit

enum SidebarTab: String, CaseIterable {
    case tunnels
    case sshConfig
}

struct TunnelListView: View {
    @Bindable var store: ConfigStore
    let processManager: SSHProcessManager
    let status: TunnelStatus

    @State private var sidebarTab: SidebarTab = .tunnels
    @State private var selection: UUID?
    @State private var sshConfigSelection: UUID?
    @State private var sshConfigStore = SSHConfigStore()
    @State private var showImport = false
    @State private var showProcesses = false
    @State private var showHelp = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("", selection: $sidebarTab) {
                    Text(String(localized: "Tunnels")).tag(SidebarTab.tunnels)
                    Text(String(localized: "SSH Config")).tag(SidebarTab.sshConfig)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

                switch sidebarTab {
                case .tunnels:
                    tunnelList
                case .sshConfig:
                    SSHConfigListView(store: sshConfigStore, selection: $sshConfigSelection)
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 300)
            .toolbar {
                switch sidebarTab {
                case .tunnels:
                    tunnelToolbar
                case .sshConfig:
                    sshConfigToolbar
                }
            }
        } detail: {
            switch sidebarTab {
            case .tunnels:
                tunnelDetail
            case .sshConfig:
                sshConfigDetail
            }
        }
        .sheet(isPresented: $showImport) {
            ImportView(store: store)
        }
        .sheet(isPresented: $showProcesses) {
            SSHProcessListView()
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .onPasteCommand(of: [.plainText]) { providers in
            handlePaste(providers)
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            if let icon = NSImage(named: "AppIcon") {
                NSApp.applicationIconImage = icon
            }
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Tunnel Tab

    private var tunnelList: some View {
        List(selection: $selection) {
            ForEach(store.configs) { config in
                TunnelRowView(config: config, state: status.state(for: config.id))
                    .tag(config.id)
                    .contextMenu {
                        Button(status.state(for: config.id).isActive
                               ? String(localized: "Disconnect")
                               : String(localized: "Connect")) {
                            processManager.toggle(config)
                        }
                        Divider()
                        Button(String(localized: "Copy Share String")) {
                            let encoded = ShareService.encode(config)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(encoded, forType: .string)
                        }
                        Divider()
                        Button(String(localized: "Delete"), role: .destructive) {
                            processManager.disconnect(config.id)
                            store.delete(config.id)
                            if selection == config.id {
                                selection = nil
                            }
                        }
                    }
            }
        }
        .overlay {
            if store.configs.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text(String(localized: "No Tunnels"))
                    } icon: {
                        Image(systemName: "apple.terminal.circle")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .foregroundStyle(.secondary)
                    }
                } description: {
                    Text(String(localized: "Add a new tunnel with + or paste a share string with ⌘V."))
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var tunnelToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                var newConfig = SSHTunnelConfig()
                newConfig.name = String(localized: "New Tunnel")
                store.add(newConfig)
                selection = newConfig.id
            } label: {
                Image(systemName: "plus")
            }
            .help(String(localized: "Add Tunnel"))
        }

        ToolbarItem(placement: .automatic) {
            Button {
                showImport = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help(String(localized: "Import from Share String"))
            .keyboardShortcut("i", modifiers: .command)
        }

        ToolbarItem(placement: .automatic) {
            Button {
                showProcesses = true
            } label: {
                Image(systemName: "cpu")
            }
            .help(String(localized: "Running SSH Processes"))
        }

        ToolbarItem(placement: .automatic) {
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help(String(localized: "Help"))
        }
    }

    @ViewBuilder
    private var tunnelDetail: some View {
        if let selectedId = selection,
           store.configs.contains(where: { $0.id == selectedId }) {
            TunnelDetailView(
                store: store,
                processManager: processManager,
                status: status,
                configId: selectedId
            )
        } else {
            ContentUnavailableView {
                Label {
                    Text(String(localized: "No Tunnel Selected"))
                } icon: {
                    Image(systemName: "apple.terminal.circle")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.secondary)
                }
            } description: {
                Text(String(localized: "Select a tunnel from the sidebar or add a new one."))
            }
        }
    }

    // MARK: - SSH Config Tab

    @ToolbarContentBuilder
    private var sshConfigToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                guard let firstFile = sshConfigStore.configFiles.first else { return }
                var newEntry = SSHConfigEntry(host: "new-host", sourceFile: firstFile)
                sshConfigStore.add(newEntry)
                sshConfigSelection = newEntry.id
            } label: {
                Image(systemName: "plus")
            }
            .help(String(localized: "Add Host"))
        }

        ToolbarItem(placement: .automatic) {
            Button {
                if let selectedId = sshConfigSelection,
                   let entry = sshConfigStore.entries.first(where: { $0.id == selectedId }) {
                    NSWorkspace.shared.open(entry.sourceFile)
                }
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help(String(localized: "Open in External Editor"))
            .disabled(sshConfigSelection == nil)
        }

        ToolbarItem(placement: .automatic) {
            Button {
                sshConfigStore.load()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(String(localized: "Reload"))
        }

        ToolbarItem(placement: .automatic) {
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help(String(localized: "Help"))
        }
    }

    @ViewBuilder
    private var sshConfigDetail: some View {
        if let selectedId = sshConfigSelection,
           sshConfigStore.entries.contains(where: { $0.id == selectedId }) {
            SSHConfigDetailView(store: sshConfigStore, entryId: selectedId)
        } else {
            ContentUnavailableView {
                Label {
                    Text(String(localized: "No Host Selected"))
                } icon: {
                    Image(systemName: "apple.terminal.circle")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.secondary)
                }
            } description: {
                Text(String(localized: "Select a host from the sidebar or add a new one."))
            }
        }
    }

    // MARK: - Paste

    private func handlePaste(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, _ in
            guard let data = data as? Data,
                  let text = String(data: data, encoding: .utf8),
                  text.hasPrefix("sshtunnel://"),
                  let config = ShareService.decode(text) else {
                return
            }
            DispatchQueue.main.async {
                showImport = true
            }
        }
    }
}
