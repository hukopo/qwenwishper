import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: controller.status.systemImage)
                VStack(alignment: .leading) {
                    Text("QwenWhisper")
                        .font(.headline)
                    Text(controller.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
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
                    Text("Whisper: \(label(for: controller.modelAvailability.whisper))")
                    Text("Qwen: \(label(for: controller.modelAvailability.qwen))")
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let snapshot = controller.lastSnapshot {
                GroupBox("Last Result") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.rewrittenText)
                            .font(.callout)
                            .lineLimit(4)
                        Text("Source: \(snapshot.sourceText)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text("Inserted via \(snapshot.insertMethod.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("Recent Logs") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(controller.diagnostics.prefix(6)) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.message)
                                    .font(.caption)
                                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 120, alignment: .topLeading)
            }

            HStack {
                Button("Diagnostics") {
                    openWindow(id: "diagnostics")
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
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
