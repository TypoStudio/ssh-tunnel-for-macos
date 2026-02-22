import SwiftUI

struct SSHProcessInfo: Identifiable {
    let id: pid_t
    let command: String
}

struct SSHProcessListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var processes: [SSHProcessInfo] = []

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(String(localized: "Running SSH Processes"))
                    .font(.headline)
                Spacer()
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .focusable(false)
            }

            if processes.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text(String(localized: "No running SSH tunnel processes found."))
                    } icon: {
                        Image(systemName: "apple.terminal.circle")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(processes) { proc in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: "PID: \(proc.id)")
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                Text(proc.command)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(String(localized: "Kill")) {
                                kill(proc.id, SIGTERM)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    refresh()
                                }
                            }
                            .foregroundStyle(.red)
                        }
                    }
                }
            }

            HStack {
                if !processes.isEmpty {
                    Button(String(localized: "Kill All")) {
                        for proc in processes {
                            kill(proc.id, SIGTERM)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            refresh()
                        }
                    }
                    .foregroundStyle(.red)
                }
                Spacer()
                Button(String(localized: "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 500, height: 350)
        .onAppear { refresh() }
    }

    private func refresh() {
        Task.detached {
            let result = Self.findSSHProcesses()
            await MainActor.run {
                processes = result
            }
        }
    }

    private static func findSSHProcesses() -> [SSHProcessInfo] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,command"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("ssh"),
                  trimmed.contains("-N") || trimmed.contains("-L") || trimmed.contains("-R") || trimmed.contains("-D"),
                  !trimmed.contains("/bin/ps"),
                  !trimmed.contains("grep") else { return nil }

            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let pid = pid_t(parts[0]) else { return nil }
            return SSHProcessInfo(id: pid, command: String(parts[1]))
        }
    }
}
