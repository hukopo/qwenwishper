import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack {
                    Image(systemName: controller.status.systemImage)
                    VStack(alignment: .leading) {
                        Text("QwenWhisper")
                            .font(.headline)
                        Text(controller.status.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("Diagnostics") {
                        openWindow(id: "diagnostics")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Button(controller.isRecordingActive ? "Stop Recording" : "Start Recording") {
                controller.toggleRecordingFromUI()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!controller.canToggleRecording)

            GroupBox("Permissions") {
                VStack(alignment: .leading, spacing: 6) {
                    Label(controller.microphoneAuthorized ? "Microphone granted" : "Microphone missing", systemImage: controller.microphoneAuthorized ? "checkmark.circle.fill" : "xmark.circle")
                    Label(controller.accessibilityAuthorized ? "Accessibility granted" : "Accessibility missing", systemImage: controller.accessibilityAuthorized ? "checkmark.circle.fill" : "xmark.circle")
                    Button("Refresh Permissions") {
                        controller.refreshPermissions(promptForAccessibility: true)
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Models") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Whisper: \(label(for: controller.modelAvailability.whisper))")
                    Text("Qwen: \(label(for: controller.modelAvailability.qwen))")
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Texts") {
                VStack(alignment: .leading, spacing: 10) {
                    CopyableTextSection(title: "After Whisper", text: controller.latestWhisperText, minHeight: 70)
                    CopyableTextSection(title: "After Qwen", text: controller.latestQwenText, minHeight: 70)
                    if let snapshot = controller.lastSnapshot {
                        Text("Inserted via \(snapshot.insertMethod.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            CopyableTextSection(title: "Recent Logs", text: controller.diagnosticsText, font: .caption.monospaced(), minHeight: 120)
        }
        .padding(14)
        .onAppear {
            controller.start()
        }
    }

    private func label(for state: ModelAvailability.State) -> String {
        switch state {
        case .idle:
            "idle"
        case .loading:
            "loading"
        case .downloading:
            "downloading"
        case .ready:
            "ready"
        case .failed(let message):
            "failed (\(message))"
        }
    }
}
