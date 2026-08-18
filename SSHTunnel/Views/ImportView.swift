import SwiftUI

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    let store: ConfigStore

    @State private var inputText = ""
    @State private var decoded: SSHTunnelConfig?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Import Tunnel Configuration"))
                .font(.headline)

            Text(String(localized: "Paste a share string or ssh command below:"))
                .foregroundStyle(.secondary)

            TextEditor(text: $inputText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 60, maxHeight: 100)
                .border(.separator)
                .onChange(of: inputText) { _, newValue in
                    decoded = ShareService.decode(newValue)
                    errorMessage = nil
                    if !newValue.isEmpty && decoded == nil {
                        errorMessage = String(localized: "Invalid share string or ssh command.")
                    }
                }
                .onAppear {
                    // Auto-fill from clipboard if it contains a share string
                    if let clip = NSPasteboard.general.string(forType: .string),
                       clip.hasPrefix("sshtunnel://") || clip.hasPrefix("ssh ") {
                        inputText = clip
                    }
                }

            if let config = decoded {
                GroupBox(String(localized: "Preview")) {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(String(localized: "Name"), value: config.name.isEmpty ? "-" : config.name)
                        LabeledContent(String(localized: "Host"), value: "\(config.username)@\(config.host):\(config.port)")
                        LabeledContent(String(localized: "Tunnels"), value: "\(config.tunnels.count) rule(s)")

                        ForEach(config.tunnels) { entry in
                            Text("  \(entry.type.displayName): \(entry.sshArgument)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(String(localized: "Import")) {
                    if let config = decoded {
                        store.add(config)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(decoded == nil)
            }
        }
        .padding()
        .frame(width: 450)
    }
}
