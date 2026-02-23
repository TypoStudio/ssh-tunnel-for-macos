import Foundation
import AppKit
import Network

@Observable
final class SSHProcessManager {
    private var processes: [UUID: Process] = [:]
    private var pipes: [UUID: Pipe] = [:]
    private var connectTimers: [UUID: DispatchWorkItem] = [:]
    var status: TunnelStatus
    var logs: [UUID: String] = [:]

    // Auto-reconnect state
    private var manualDisconnects = Set<UUID>()
    private var pendingReconnect = Set<UUID>()
    private var reconnectConfigs: [UUID: SSHTunnelConfig] = [:]
    private var reconnectTimers: [UUID: DispatchWorkItem] = [:]
    private var retryCounts: [UUID: Int] = [:]
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true

    init(status: TunnelStatus) {
        self.status = status
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                let wasAvailable = self.isNetworkAvailable
                self.isNetworkAvailable = path.status == .satisfied
                if !wasAvailable && path.status == .satisfied {
                    self.reconnectPending()
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    /// Returns local ports that are already in use
    func checkPortConflicts(_ config: SSHTunnelConfig) -> [UInt16] {
        config.tunnels.compactMap { entry in
            let port = entry.localPort
            guard port > 0 else { return nil }
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else { return nil }
            defer { close(sock) }

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            return result != 0 ? port : nil
        }
    }

    func connect(_ config: SSHTunnelConfig) {
        let id = config.id
        guard !status.state(for: id).isActive else { return }

        reconnectConfigs[id] = config
        pendingReconnect.remove(id)
        reconnectTimers[id]?.cancel()
        reconnectTimers.removeValue(forKey: id)
        retryCounts.removeValue(forKey: id)
        manualDisconnects.remove(id)

        status.states[id] = .connecting

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = buildArguments(for: config)

        // If using password auth, use SSH_ASKPASS to provide it
        if config.authMethod == .password,
           let password = KeychainService.getPassword(for: config.id) {
            let askpassScript = createAskPassScript(password: password, configId: config.id)
            var env = ProcessInfo.processInfo.environment
            env["SSH_ASKPASS"] = askpassScript
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"] = ":0"
            process.environment = env
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipes[id] = pipe

        // Collect log output from ssh stderr/stdout
        logs[id] = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.logs[id, default: ""].append(output)
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                self.cleanupAskPassScript(configId: id)
                self.connectTimers[id]?.cancel()
                self.connectTimers.removeValue(forKey: id)
                self.processes.removeValue(forKey: id)
                self.pipes[id]?.fileHandleForReading.readabilityHandler = nil
                self.pipes.removeValue(forKey: id)

                if proc.terminationStatus == 0 {
                    self.status.states[id] = .disconnected
                } else if self.status.state(for: id) == .connecting {
                    self.status.states[id] = .error(String(localized: "Connection failed (exit \(proc.terminationStatus))"))
                } else {
                    self.status.states[id] = .disconnected
                    // Auto-reconnect on unexpected disconnect
                    if !self.manualDisconnects.contains(id),
                       let config = self.reconnectConfigs[id],
                       config.autoReconnect {
                        self.pendingReconnect.insert(id)
                        if self.isNetworkAvailable {
                            self.scheduleReconnect(id)
                        }
                    }
                }
                self.manualDisconnects.remove(id)
            }
        }

        do {
            try process.run()
            processes[id] = process

            // Timer-based connection detection:
            // If process is still alive after 3 seconds, consider it connected
            let timer = DispatchWorkItem { [weak self] in
                guard let self, let proc = self.processes[id], proc.isRunning else { return }
                self.status.states[id] = .connected
            }
            connectTimers[id] = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timer)
        } catch {
            status.states[id] = .error(error.localizedDescription)
        }
    }

    func disconnect(_ configId: UUID) {
        manualDisconnects.insert(configId)
        pendingReconnect.remove(configId)
        reconnectTimers[configId]?.cancel()
        reconnectTimers.removeValue(forKey: configId)
        retryCounts.removeValue(forKey: configId)

        connectTimers[configId]?.cancel()
        connectTimers.removeValue(forKey: configId)

        guard let process = processes[configId], process.isRunning else {
            status.states[configId] = .disconnected
            return
        }
        process.terminate()
    }

    func toggle(_ config: SSHTunnelConfig) {
        if status.state(for: config.id).isActive {
            disconnect(config.id)
        } else {
            connect(config)
        }
    }

    func disconnectAll() {
        for id in processes.keys {
            disconnect(id)
        }
    }

    func disconnectOnQuit(configs: [SSHTunnelConfig]) {
        for config in configs where config.disconnectOnQuit {
            disconnect(config.id)
        }
    }

    private func buildArguments(for config: SSHTunnelConfig) -> [String] {
        var args: [String] = [
            "-N",
            "-v",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "StrictHostKeyChecking=accept-new",
            "-p", "\(config.port)",
        ]

        switch config.authMethod {
        case .identityFile:
            if !config.identityFile.isEmpty {
                args += ["-i", config.identityFile]
            }
            args += ["-o", "PasswordAuthentication=no"]
        case .password:
            args += ["-o", "PreferredAuthentications=password,keyboard-interactive"]
        }

        for entry in config.tunnels {
            args += [entry.type.flag, entry.sshArgument]
        }

        if !config.additionalArgs.isEmpty {
            let extra = config.additionalArgs
                .split(separator: " ")
                .map(String.init)
            args += extra
        }

        args.append("\(config.username)@\(config.host)")
        return args
    }

    // MARK: - Auto-reconnect

    private func scheduleReconnect(_ id: UUID) {
        reconnectTimers[id]?.cancel()
        let count = retryCounts[id, default: 0]
        let delays = [3.0, 5.0, 10.0, 30.0, 60.0]
        let delay = delays[min(count, delays.count - 1)]
        let timer = DispatchWorkItem { [weak self] in
            guard let self,
                  self.pendingReconnect.contains(id),
                  let config = self.reconnectConfigs[id] else { return }
            self.retryCounts[id] = count + 1
            self.connect(config)
        }
        reconnectTimers[id] = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: timer)
    }

    private func reconnectPending() {
        for id in pendingReconnect {
            retryCounts[id] = 0
            scheduleReconnect(id)
        }
    }

    func cancelReconnect(_ configId: UUID) {
        pendingReconnect.remove(configId)
        reconnectTimers[configId]?.cancel()
        reconnectTimers.removeValue(forKey: configId)
        retryCounts.removeValue(forKey: configId)
        reconnectConfigs.removeValue(forKey: configId)
    }

    // MARK: - SSH_ASKPASS helper

    private func createAskPassScript(password: String, configId: UUID) -> String {
        let tmpDir = FileManager.default.temporaryDirectory
        let scriptPath = tmpDir.appendingPathComponent("sshtunnel-askpass-\(configId.uuidString).sh").path
        let escaped = password.replacingOccurrences(of: "'", with: "'\\''")
        let content = "#!/bin/sh\necho '\(escaped)'\n"
        FileManager.default.createFile(atPath: scriptPath, contents: content.data(using: .utf8), attributes: [.posixPermissions: 0o700])
        return scriptPath
    }

    private func cleanupAskPassScript(configId: UUID) {
        let tmpDir = FileManager.default.temporaryDirectory
        let scriptPath = tmpDir.appendingPathComponent("sshtunnel-askpass-\(configId.uuidString).sh").path
        try? FileManager.default.removeItem(atPath: scriptPath)
    }
}
