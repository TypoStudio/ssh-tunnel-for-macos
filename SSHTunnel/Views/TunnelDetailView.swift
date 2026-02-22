import SwiftUI

struct TunnelDetailView: View {
    @Bindable var store: ConfigStore
    let processManager: SSHProcessManager
    let status: TunnelStatus
    var configId: UUID

    @State private var draft: SSHTunnelConfig = SSHTunnelConfig()
    @State private var showCopied = false
    @State private var password: String = ""
    @Environment(\.openWindow) private var openWindow
    @State private var showSSHConfig = false
    @State private var portConflictAlert = false
    @State private var conflictingPorts: [UInt16] = []

    private var state: ConnectionState {
        status.state(for: configId)
    }

    var body: some View {
        Form {
            Section(String(localized: "Connection")) {
                TextField(String(localized: "Name"), text: $draft.name)
                TextField(String(localized: "Host"), text: $draft.host)
                TextField(String(localized: "Port"), text: Binding(
                    get: { draft.port == 22 ? "22" : "\(draft.port)" },
                    set: { draft.port = UInt16($0) ?? 22 }
                ))
                TextField(String(localized: "Username"), text: $draft.username)
            }

            Section(String(localized: "Authentication")) {
                Picker(String(localized: "Method"), selection: $draft.authMethod) {
                    ForEach(AuthMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                switch draft.authMethod {
                case .identityFile:
                    HStack {
                        TextField(String(localized: "Identity File"), text: $draft.identityFile)
                        Button(String(localized: "Browse...")) {
                            browseIdentityFile()
                        }
                    }
                case .password:
                    SecureField(String(localized: "Password"), text: $password)
                        .onChange(of: password) { _, newValue in
                            if newValue.isEmpty {
                                KeychainService.deletePassword(for: draft.id)
                            } else {
                                KeychainService.savePassword(newValue, for: draft.id)
                            }
                        }
                }
            }

            Section(String(localized: "Port Forwarding")) {
                if !draft.tunnels.isEmpty {
                    TunnelEntryHeader()
                }

                ForEach($draft.tunnels) { $entry in
                    TunnelEntryEditor(entry: $entry) {
                        draft.tunnels.removeAll { $0.id == entry.id }
                    }
                }

                Button {
                    draft.tunnels.append(TunnelEntry())
                } label: {
                    Label(String(localized: "Add Rule"), systemImage: "plus")
                }
            }

            Section(String(localized: "Options")) {
                Toggle(String(localized: "Auto-connect on launch"), isOn: $draft.autoConnect)
                Toggle(String(localized: "Disconnect on quit"), isOn: $draft.disconnectOnQuit)
                TextField(String(localized: "Additional SSH Arguments"), text: $draft.additionalArgs)
            }

            Section(String(localized: "Share")) {
                HStack {
                    Button {
                        let encoded = ShareService.encode(draft)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(encoded, forType: .string)
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showCopied = false
                        }
                    } label: {
                        Label(String(localized: "Copy Share String"), systemImage: "doc.on.doc")
                    }

                    Button {
                        let cli = ShareService.buildCLI(draft)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cli, forType: .string)
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showCopied = false
                        }
                    } label: {
                        Label(String(localized: "Copy CLI Command"), systemImage: "terminal")
                    }

                    if showCopied {
                        Text(String(localized: "Copied!"))
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadDraft() }
        .onChange(of: configId) { _, _ in loadDraft() }
        .onChange(of: draft) { _, newValue in
            store.update(newValue)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showSSHConfig = true
                } label: {
                    Image(systemName: "doc.text")
                }
                .help(String(localized: "Load from SSH Config"))
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    openWindow(id: "log", value: configId)
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .help(String(localized: "Connection Log"))
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    attemptConnect()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(state.color)
                            .frame(width: 8, height: 8)
                        Text(state.isActive
                             ? String(localized: "Disconnect")
                             : String(localized: "Connect"))
                    }
                }
                .disabled(draft.host.isEmpty || draft.username.isEmpty || draft.tunnels.isEmpty)
            }
        }
        .sheet(isPresented: $showSSHConfig) {
            SSHConfigPickerView { host in
                applySSHConfig(host)
            }
        }
        .alert(String(localized: "Port Conflict"), isPresented: $portConflictAlert) {
            Button(String(localized: "Connect Anyway")) {
                processManager.connect(draft)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            let ports = conflictingPorts.map(String.init).joined(separator: ", ")
            Text(String(localized: "Port \(ports) is already in use. The connection may fail."))
        }
    }

    private func attemptConnect() {
        if state.isActive {
            processManager.disconnect(draft.id)
            return
        }
        let conflicts = processManager.checkPortConflicts(draft)
        if conflicts.isEmpty {
            processManager.connect(draft)
        } else {
            conflictingPorts = conflicts
            portConflictAlert = true
        }
    }

    private func loadDraft() {
        if let config = store.configs.first(where: { $0.id == configId }) {
            draft = config
            password = KeychainService.getPassword(for: config.id) ?? ""
        }
    }

    private func applySSHConfig(_ host: SSHConfigHost) {
        if draft.name.isEmpty || draft.name == String(localized: "New Tunnel") {
            draft.name = host.name
        }
        draft.host = host.hostname
        draft.port = host.port
        if !host.user.isEmpty { draft.username = host.user }
        if !host.identityFile.isEmpty {
            draft.authMethod = .identityFile
            draft.identityFile = host.identityFile
        }
    }

    private func browseIdentityFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url {
            draft.identityFile = url.path
        }
    }
}

// MARK: - SSH Config Picker Sheet

struct SSHConfigPickerView: View {
    let onSelect: (SSHConfigHost) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hosts: [SSHConfigHost] = []
    @State private var searchText = ""

    private var filtered: [SSHConfigHost] {
        if searchText.isEmpty { return hosts }
        let query = searchText.lowercased()
        return hosts.filter {
            $0.name.lowercased().contains(query) ||
            $0.hostname.lowercased().contains(query) ||
            $0.user.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(String(localized: "Load from SSH Config"))
                    .font(.headline)
                Spacer()
            }

            TextField(String(localized: "Search"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            if hosts.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text(String(localized: "No SSH Config Found"))
                    } icon: {
                        Image(systemName: "apple.terminal.circle")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .foregroundStyle(.secondary)
                    }
                } description: {
                    Text(String(localized: "No hosts found in ~/.ssh/config"))
                }
                .frame(maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
            } else {
                List(filtered) { host in
                    Button {
                        onSelect(host)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(host.name)
                                    .fontWeight(.medium)
                                Text("\(host.user.isEmpty ? "" : "\(host.user)@")\(host.hostname)\(host.port != 22 ? ":\(host.port)" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
        .onAppear {
            hosts = SSHConfigParser.parse()
        }
    }
}

// MARK: - Log View

struct LogView: View {
    let configId: UUID
    let processManager: SSHProcessManager

    private var log: String {
        processManager.logs[configId] ?? String(localized: "No log available.")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                    Color.clear
                        .frame(height: 0)
                        .id("bottom")
                }
                .onChange(of: log) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottom")
                    }
                }
                .onAppear {
                    proxy.scrollTo("bottom")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    let text = processManager.logs[configId] ?? ""
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help(String(localized: "Copy Log"))
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    processManager.logs[configId] = ""
                } label: {
                    Image(systemName: "trash")
                }
                .help(String(localized: "Clear Log"))
            }
        }
    }
}
