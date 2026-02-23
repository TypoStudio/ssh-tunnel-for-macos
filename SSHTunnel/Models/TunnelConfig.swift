import Foundation

enum TunnelType: String, Codable, CaseIterable, Identifiable {
    case local
    case remote
    case dynamic

    var id: String { rawValue }

    var flag: String {
        switch self {
        case .local: "-L"
        case .remote: "-R"
        case .dynamic: "-D"
        }
    }

    var displayName: String {
        switch self {
        case .local: String(localized: "Local (-L)")
        case .remote: String(localized: "Remote (-R)")
        case .dynamic: String(localized: "Dynamic (-D)")
        }
    }
}

struct TunnelEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var type: TunnelType = .local
    var localPort: UInt16 = 0
    var remoteHost: String = "localhost"
    var remotePort: UInt16 = 0
    var bindAddress: String = ""

    var sshArgument: String {
        let bind = bindAddress.isEmpty ? "" : "\(bindAddress):"
        switch type {
        case .local, .remote:
            return "\(bind)\(localPort):\(remoteHost):\(remotePort)"
        case .dynamic:
            return "\(bind)\(localPort)"
        }
    }
}

enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case identityFile
    case password

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .identityFile: String(localized: "Identity File")
        case .password: String(localized: "Password")
        }
    }
}

struct SSHTunnelConfig: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var host: String = ""
    var port: UInt16 = 22
    var username: String = ""
    var authMethod: AuthMethod = .identityFile
    var identityFile: String = ""
    var tunnels: [TunnelEntry] = []
    var autoConnect: Bool = false
    var disconnectOnQuit: Bool = true
    var autoReconnect: Bool = true
    var additionalArgs: String = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(UInt16.self, forKey: .port)
        username = try c.decode(String.self, forKey: .username)
        authMethod = try c.decode(AuthMethod.self, forKey: .authMethod)
        identityFile = try c.decode(String.self, forKey: .identityFile)
        tunnels = try c.decode([TunnelEntry].self, forKey: .tunnels)
        autoConnect = try c.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? false
        disconnectOnQuit = try c.decodeIfPresent(Bool.self, forKey: .disconnectOnQuit) ?? true
        autoReconnect = try c.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? true
        additionalArgs = try c.decodeIfPresent(String.self, forKey: .additionalArgs) ?? ""
    }

    init() {}
}
