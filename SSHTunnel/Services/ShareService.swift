import Foundation

/// Share format (plain text):
/// ```
/// sshtunnel://user@host:port/name
/// L:localPort:remoteHost:remotePort
/// R:localPort:remoteHost:remotePort
/// D:localPort
/// ```
enum ShareService {
    static func encode(_ config: SSHTunnelConfig) -> String {
        let name = config.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.name
        var lines: [String] = [
            "sshtunnel://\(config.username)@\(config.host):\(config.port)/\(name)"
        ]

        for entry in config.tunnels {
            switch entry.type {
            case .local:
                lines.append("L:\(entry.localPort):\(entry.remoteHost):\(entry.remotePort)")
            case .remote:
                lines.append("R:\(entry.localPort):\(entry.remoteHost):\(entry.remotePort)")
            case .dynamic:
                lines.append("D:\(entry.localPort)")
            }
        }

        return lines.joined(separator: "\n")
    }

    static func buildCLI(_ config: SSHTunnelConfig) -> String {
        var args = ["ssh", "-N"]

        if config.port != 22 {
            args += ["-p", "\(config.port)"]
        }

        switch config.authMethod {
        case .identityFile:
            if !config.identityFile.isEmpty {
                args += ["-i", config.identityFile]
            }
        case .password:
            args += ["-o", "PreferredAuthentications=password,keyboard-interactive"]
        }

        for entry in config.tunnels {
            args += [entry.type.flag, entry.sshArgument]
        }

        if !config.additionalArgs.isEmpty {
            args.append(config.additionalArgs)
        }

        args.append("\(config.username)@\(config.host)")
        return args.joined(separator: " ")
    }

    static func decode(_ input: String) -> SSHTunnelConfig? {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Support legacy base64 format
        if raw.hasPrefix("sshtunnel://") && !raw.contains("@") {
            return decodeLegacyBase64(raw)
        }

        let lines = raw.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let header = lines.first, header.hasPrefix("sshtunnel://") else {
            // Not a share string: fall back to parsing an ssh command line.
            return parseCLI(raw)
        }

        // Parse: sshtunnel://user@host:port/name
        let uri = String(header.dropFirst("sshtunnel://".count))

        guard let atIndex = uri.firstIndex(of: "@") else { return nil }
        let user = String(uri[uri.startIndex..<atIndex])

        let afterAt = String(uri[uri.index(after: atIndex)...])

        // Split host:port/name
        var hostPart = afterAt
        var name = ""
        if let slashIndex = afterAt.firstIndex(of: "/") {
            hostPart = String(afterAt[afterAt.startIndex..<slashIndex])
            name = String(afterAt[afterAt.index(after: slashIndex)...])
                .removingPercentEncoding ?? ""
        }

        let hostComponents = hostPart.split(separator: ":", maxSplits: 1)
        let host = String(hostComponents[0])
        let port: UInt16 = hostComponents.count > 1 ? UInt16(hostComponents[1]) ?? 22 : 22

        // Parse tunnel entries
        var tunnels: [TunnelEntry] = []
        for line in lines.dropFirst() {
            if let entry = parseTunnelLine(line) {
                tunnels.append(entry)
            }
        }

        var config = SSHTunnelConfig()
        config.id = UUID()
        config.name = name
        config.host = host
        config.port = port
        config.username = user
        config.tunnels = tunnels
        return config
    }

    private static func parseTunnelLine(_ line: String) -> TunnelEntry? {
        let parts = line.split(separator: ":", maxSplits: 3).map(String.init)
        guard parts.count >= 2 else { return nil }

        let typeStr = parts[0].uppercased()
        var entry = TunnelEntry()

        switch typeStr {
        case "L":
            guard parts.count == 4,
                  let lp = UInt16(parts[1]),
                  let rp = UInt16(parts[3]) else { return nil }
            entry.type = .local
            entry.localPort = lp
            entry.remoteHost = parts[2]
            entry.remotePort = rp
        case "R":
            guard parts.count == 4,
                  let lp = UInt16(parts[1]),
                  let rp = UInt16(parts[3]) else { return nil }
            entry.type = .remote
            entry.localPort = lp
            entry.remoteHost = parts[2]
            entry.remotePort = rp
        case "D":
            guard let lp = UInt16(parts[1]) else { return nil }
            entry.type = .dynamic
            entry.localPort = lp
        default:
            return nil
        }
        return entry
    }

    // Support for old base64 format
    private static func decodeLegacyBase64(_ raw: String) -> SSHTunnelConfig? {
        let base64 = String(raw.dropFirst("sshtunnel://".count))
        guard let data = Data(base64Encoded: base64) else { return nil }
        var config = try? JSONDecoder().decode(SSHTunnelConfig.self, from: data)
        config?.id = UUID()
        return config
    }

    // MARK: - CLI parsing

    /// Options that take a separate value which is preserved verbatim in `additionalArgs`.
    private static let passthroughValueOptions: Set<String> = [
        "-b", "-c", "-E", "-e", "-F", "-I", "-J", "-m", "-O", "-Q", "-S", "-W", "-w"
    ]

    /// Parses an `ssh` command line (the format produced by `buildCLI`) into a config.
    static func parseCLI(_ input: String) -> SSHTunnelConfig? {
        var tokens = tokenize(input)
        if let first = tokens.first,
           first == "ssh" || first.hasSuffix("/ssh") || first.lowercased().hasSuffix("ssh.exe") {
            tokens.removeFirst()
        }
        guard !tokens.isEmpty else { return nil }

        var config = SSHTunnelConfig()
        var extra: [String] = []
        var destination: String?
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            index += 1

            guard token.hasPrefix("-"), token.count > 1 else {
                // First bare token is the destination; anything after it is a remote command.
                if destination == nil && !token.isEmpty { destination = token }
                continue
            }

            let flag = String(token.prefix(2))
            let inline = String(token.dropFirst(2))

            func nextValue() -> String? {
                if !inline.isEmpty { return inline }
                guard index < tokens.count else { return nil }
                let value = tokens[index]
                index += 1
                return value
            }

            switch flag {
            case "-p":
                if let value = nextValue(), let port = UInt16(value) { config.port = port }
            case "-i":
                if let value = nextValue() {
                    config.authMethod = .identityFile
                    config.identityFile = value
                }
            case "-l":
                if let value = nextValue() { config.username = value }
            case "-L", "-R", "-D":
                if let type = forwardType(for: flag),
                   let value = nextValue(),
                   let entry = parseForwardArgument(value, type: type) {
                    config.tunnels.append(entry)
                }
            case "-o":
                if let value = nextValue() {
                    if value.hasPrefix("PreferredAuthentications=") && value.contains("password") {
                        config.authMethod = .password
                    } else {
                        extra += ["-o", value]
                    }
                }
            case "-N", "-v":
                break // always applied when launching
            default:
                if passthroughValueOptions.contains(flag), let value = nextValue() {
                    extra += [flag, value]
                } else {
                    extra.append(token)
                }
            }
        }

        // A tunnel command without any forwarding rule is not a tunnel config.
        guard var target = destination, !config.tunnels.isEmpty else { return nil }
        if target.hasPrefix("ssh://") { target = String(target.dropFirst("ssh://".count)) }
        if let atIndex = target.lastIndex(of: "@") {
            config.username = String(target[target.startIndex..<atIndex])
            target = String(target[target.index(after: atIndex)...])
        }
        let hostComponents = target.split(separator: ":")
        if hostComponents.count == 2, let port = UInt16(hostComponents[1]) {
            config.port = port
            target = String(hostComponents[0])
        }
        guard !target.isEmpty else { return nil }

        config.host = target
        config.name = target
        config.additionalArgs = extra.joined(separator: " ")
        return config
    }

    /// Parses forwarding rules out of CLI-style text. Accepts `-L 8080:localhost:80`,
    /// `-D1080`, share lines like `L:8080:localhost:80`, and a bare `8080:localhost:80`
    /// (treated as local). Non-forwarding tokens are ignored.
    static func parseForwardingEntries(_ input: String) -> [TunnelEntry] {
        let tokens = tokenize(input)
        var entries: [TunnelEntry] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            index += 1

            if token.hasPrefix("-") {
                guard token.count > 1, let type = forwardType(for: String(token.prefix(2))) else { continue }
                var value = String(token.dropFirst(2))
                if value.isEmpty {
                    guard index < tokens.count else { break }
                    value = tokens[index]
                    index += 1
                }
                if let entry = parseForwardArgument(value, type: type) { entries.append(entry) }
            } else if let entry = parseTunnelLine(token) {
                entries.append(entry)
            } else if let entry = parseForwardArgument(token, type: .local) {
                entries.append(entry)
            }
        }
        return entries
    }

    private static func forwardType(for flag: String) -> TunnelType? {
        switch flag {
        case "-L": .local
        case "-R": .remote
        case "-D": .dynamic
        default: nil
        }
    }

    /// Parses `[bind:]port:host:hostport` (-L/-R) or `[bind:]port` (-D).
    private static func parseForwardArgument(_ argument: String, type: TunnelType) -> TunnelEntry? {
        let parts = argument.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var entry = TunnelEntry()
        entry.type = type

        switch type {
        case .local, .remote:
            switch parts.count {
            case 3:
                guard let localPort = UInt16(parts[0]), let remotePort = UInt16(parts[2]) else { return nil }
                entry.localPort = localPort
                entry.remoteHost = parts[1]
                entry.remotePort = remotePort
            case 4:
                guard let localPort = UInt16(parts[1]), let remotePort = UInt16(parts[3]) else { return nil }
                entry.bindAddress = parts[0]
                entry.localPort = localPort
                entry.remoteHost = parts[2]
                entry.remotePort = remotePort
            default:
                return nil
            }
        case .dynamic:
            switch parts.count {
            case 1:
                guard let localPort = UInt16(parts[0]) else { return nil }
                entry.localPort = localPort
            case 2:
                guard let localPort = UInt16(parts[1]) else { return nil }
                entry.bindAddress = parts[0]
                entry.localPort = localPort
            default:
                return nil
            }
        }

        if type != .dynamic && entry.remoteHost.isEmpty { return nil }
        return entry
    }

    /// Splits a command line on whitespace, honoring quotes and line continuations.
    /// Backslashes are literal so that Windows paths survive round-tripping.
    private static func tokenize(_ input: String) -> [String] {
        let joined = input
            .replacingOccurrences(of: "\\\r\n", with: " ")
            .replacingOccurrences(of: "\\\n", with: " ")
        var tokens: [String] = []
        var current = ""
        var hasToken = false
        var quote: Character?

        for character in joined {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
                hasToken = true
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                hasToken = true
                continue
            }
            if character.isWhitespace {
                if hasToken { tokens.append(current) }
                current = ""
                hasToken = false
                continue
            }
            current.append(character)
            hasToken = true
        }
        if hasToken { tokens.append(current) }
        return tokens
    }
}
