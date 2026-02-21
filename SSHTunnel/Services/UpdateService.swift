import AppKit
import Foundation

struct UpdateInfo {
    let version: String
    let htmlURL: URL
    let dmgURL: URL?
}

enum UpdateService {
    private struct GitHubRelease: Codable {
        let tagName: String
        let htmlUrl: String
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case assets
        }
    }

    private struct GitHubAsset: Codable {
        let name: String
        let browserDownloadUrl: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    static func checkForUpdate() async -> UpdateInfo? {
        guard let url = URL(string: "https://api.github.com/repos/TypoStudio/ssh-tunnel-for-macos/releases/latest") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              let htmlURL = URL(string: release.htmlUrl) else {
            return nil
        }

        let remoteVersion = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

        guard isNewer(remote: remoteVersion, current: currentVersion) else {
            return nil
        }

        let dmgURL = release.assets
            .first { $0.name.hasSuffix(".dmg") }
            .flatMap { URL(string: $0.browserDownloadUrl) }

        return UpdateInfo(version: remoteVersion, htmlURL: htmlURL, dmgURL: dmgURL)
    }

    /// Download DMG with progress, mount, replace app, relaunch. Throws on failure.
    static func performUpdate(dmgURL: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        // 1. Download DMG with progress
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kr.typostudio.sshtunnel", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let dmgPath = cacheDir.appendingPathComponent("update.dmg")
        try? FileManager.default.removeItem(at: dmgPath)

        let downloadedURL = try await downloadWithProgress(from: dmgURL, progressHandler: progressHandler)
        try FileManager.default.moveItem(at: downloadedURL, to: dmgPath)

        // Verify downloaded file
        let attrs = try FileManager.default.attributesOfItem(atPath: dmgPath.path)
        let fileSize = attrs[.size] as? Int ?? 0
        if fileSize < 1024 {
            throw UpdateError.downloadFailed
        }

        // 2. Mount DMG
        let mountPoint = try mountDMG(at: dmgPath.path)

        defer {
            // 4. Cleanup
            unmountDMG(at: mountPoint)
            try? FileManager.default.removeItem(at: dmgPath)
        }

        // 3. Find .app in mount and replace
        let contents = try FileManager.default.contentsOfDirectory(atPath: mountPoint)
        guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError.appNotFoundInDMG
        }

        let sourceApp = mountPoint + "/" + appName
        let currentAppPath = Bundle.main.bundlePath
        let parentDir = (currentAppPath as NSString).deletingLastPathComponent
        let destApp = parentDir + "/" + appName

        // Remove old app and copy new one
        let rm = Process()
        rm.executableURL = URL(fileURLWithPath: "/bin/rm")
        rm.arguments = ["-rf", currentAppPath]
        try rm.run()
        rm.waitUntilExit()
        guard rm.terminationStatus == 0 else { throw UpdateError.replaceFailed }

        let cp = Process()
        cp.executableURL = URL(fileURLWithPath: "/bin/cp")
        cp.arguments = ["-R", sourceApp, destApp]
        try cp.run()
        cp.waitUntilExit()
        guard cp.terminationStatus == 0 else { throw UpdateError.replaceFailed }

        // Remove quarantine attribute
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-rd", "com.apple.quarantine", destApp]
        try? xattr.run()
        xattr.waitUntilExit()

        // 5. Relaunch
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [destApp]
        try open.run()

        await MainActor.run {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Private

    private static func downloadWithProgress(from url: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(
                progressHandler: progressHandler,
                completion: { result in
                    continuation.resume(with: result)
                }
            )
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    private static func mountDMG(at path: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", path, "-nobrowse", "-noverify", "-noautoopen", "-plist"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Prevent interactive prompts (e.g. EULA acceptance)
        process.standardInput = FileHandle.nullDevice

        try process.run()

        // Read pipes before waitUntilExit to avoid deadlock when pipe buffer fills
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw UpdateError.mountFailedWithMessage(stderrStr)
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: stdoutData, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw UpdateError.mountFailedWithMessage("Failed to parse plist output")
        }

        guard let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw UpdateError.mountFailedWithMessage("No mount point found in plist")
        }

        return mountPoint
    }

    private static func unmountDMG(at mountPoint: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint, "-quiet"]
        try? process.run()
        process.waitUntilExit()
    }

    private static func isNewer(remote: String, current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }
}

// MARK: - Download Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progressHandler: @Sendable (Double) -> Void
    private let completion: (Result<URL, Error>) -> Void
    private var tempFileURL: URL?

    init(progressHandler: @escaping @Sendable (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        self.progressHandler = progressHandler
        self.completion = completion
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move to a temp location that won't be deleted when this method returns
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dmg")
        do {
            try FileManager.default.moveItem(at: location, to: temp)
            tempFileURL = temp
        } catch {
            completion(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            completion(.failure(error))
        } else if let tempFileURL {
            completion(.success(tempFileURL))
        } else {
            completion(.failure(UpdateError.downloadFailed))
        }
        session.invalidateAndCancel()
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case appNotFoundInDMG
    case mountFailedWithMessage(String)
    case replaceFailed
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .appNotFoundInDMG: return "App not found in DMG"
        case .mountFailedWithMessage(let msg): return "Failed to mount DMG: \(msg)"
        case .replaceFailed: return "Failed to replace app"
        case .downloadFailed: return "Download failed"
        }
    }
}

// MARK: - Alert Functions

@MainActor
func showUpdateAlert(info: UpdateInfo) {
    let alert = NSAlert()
    alert.messageText = String(localized: "Update Available")
    alert.informativeText = String(localized: "A new version \(info.version) is available.")

    if info.dmgURL != nil {
        alert.addButton(withTitle: String(localized: "Install and Restart"))
    }
    alert.addButton(withTitle: String(localized: "Download"))
    alert.addButton(withTitle: String(localized: "Later"))
    alert.alertStyle = .informational

    let response = alert.runModal()

    if info.dmgURL != nil {
        switch response {
        case .alertFirstButtonReturn:
            performAutoUpdate(info: info)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(info.htmlURL)
        default:
            break
        }
    } else {
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(info.htmlURL)
        }
    }
}

@MainActor
func showUpToDateAlert() {
    let alert = NSAlert()
    alert.messageText = String(localized: "You're up to date.")
    alert.informativeText = String(localized: "SSH Tunnel Manager %@", defaultValue: "SSH Tunnel Manager \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
    alert.addButton(withTitle: String(localized: "OK"))
    alert.alertStyle = .informational
    alert.runModal()
}

@MainActor
private func performAutoUpdate(info: UpdateInfo) {
    guard let dmgURL = info.dmgURL else { return }

    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 130),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    panel.title = String(localized: "Installing Update...")
    panel.isReleasedWhenClosed = false
    panel.center()
    panel.level = .floating

    let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 130))

    let label = NSTextField(labelWithString: String(localized: "Downloading %@...", defaultValue: "Downloading \(info.version)..."))
    label.frame = NSRect(x: 20, y: 80, width: 280, height: 20)
    label.alignment = .center
    contentView.addSubview(label)

    let percentLabel = NSTextField(labelWithString: "0%")
    percentLabel.frame = NSRect(x: 20, y: 55, width: 280, height: 20)
    percentLabel.alignment = .center
    percentLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    contentView.addSubview(percentLabel)

    let progressBar = NSProgressIndicator()
    progressBar.style = .bar
    progressBar.isIndeterminate = false
    progressBar.minValue = 0
    progressBar.maxValue = 1
    progressBar.doubleValue = 0
    progressBar.frame = NSRect(x: 20, y: 30, width: 280, height: 20)
    contentView.addSubview(progressBar)

    panel.contentView = contentView
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    Task {
        do {
            try await UpdateService.performUpdate(dmgURL: dmgURL) { progress in
                Task { @MainActor in
                    progressBar.doubleValue = progress
                    let percent = Int(progress * 100)
                    percentLabel.stringValue = "\(percent)%"
                    if progress >= 1.0 {
                        label.stringValue = String(localized: "Installing %@...", defaultValue: "Installing \(info.version)...")
                        percentLabel.isHidden = true
                        progressBar.isIndeterminate = true
                        progressBar.startAnimation(nil)
                    }
                }
            }
        } catch {
            panel.close()
            let errorAlert = NSAlert()
            errorAlert.messageText = String(localized: "Update Failed")
            errorAlert.informativeText = error.localizedDescription
            errorAlert.addButton(withTitle: String(localized: "Download Manually"))
            errorAlert.addButton(withTitle: String(localized: "OK"))
            errorAlert.alertStyle = .warning

            if errorAlert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(info.htmlURL)
            }
        }
    }
}
