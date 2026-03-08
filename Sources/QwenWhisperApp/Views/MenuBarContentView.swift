import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

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
                    Button("Settings") {
                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

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
                VStack(alignment: .leading, spacing: 6) {
                    ModelStatusRow(label: "Whisper", state: controller.modelAvailability.whisper) {
                        controller.retryModel(.whisper)
                    }
                    ModelStatusRow(label: "Qwen", state: controller.modelAvailability.qwen) {
                        controller.retryModel(.qwen)
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Texts") {
                VStack(alignment: .leading, spacing: 10) {
                    if controller.settings.qwenEnabled {
                        CopyableTextSection(title: "After Whisper", text: controller.latestWhisperText, minHeight: 70)
                        CopyableTextSection(title: "After Qwen", text: controller.latestQwenText, minHeight: 70)
                    } else {
                        CopyableTextSection(title: "Transcribed text", text: controller.latestWhisperText, minHeight: 70)
                    }
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

}

private struct ModelStatusRow: View {
    let label: String
    let state: ModelAvailability.State
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("\(label): \(stateLabel)")
                if case .failed = state {
                    Button("Retry") { onRetry() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            }
            if case .downloading(let fraction) = state, fraction > 0 {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)
            } else if state == .loading || state == .processing {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)
            }
        }
    }

    private var stateLabel: String {
        switch state {
        case .idle:             return "idle"
        case .loading:          return "loading…"
        case .processing:       return label == "Whisper" ? "transcribing…" : "rewriting…"
        case .downloading(let f):
            return f > 0.001 ? "downloading \(Int(f * 100))%" : "downloading…"
        case .ready:            return "ready"
        case .failed:           return "failed"
        case .disabled:         return "disabled"
        }
    }
}
