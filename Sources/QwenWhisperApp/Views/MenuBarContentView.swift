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

            VStack(alignment: .leading, spacing: 8) {
                Button(controller.isRecordingActive ? "Stop Recording" : "Start Recording") {
                    controller.toggleRecordingFromUI()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.canToggleRecording)

                Button(controller.isLiveTranslationActive ? "Stop Live Translation" : "Start Live Translation") {
                    controller.toggleLiveTranslationFromUI()
                }
                .buttonStyle(.bordered)
                .disabled(!controller.canToggleLiveTranslation)

                Text("Live mode: \(controller.settings.liveAudioSource.title) -> \(controller.settings.liveTranslationTargetLanguage.title)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GroupBox("Permissions") {
                VStack(alignment: .leading, spacing: 6) {
                    Label(controller.microphoneAuthorized ? "Microphone granted" : "Microphone missing", systemImage: controller.microphoneAuthorized ? "checkmark.circle.fill" : "xmark.circle")
                    Label(controller.screenCaptureAuthorized ? "Screen capture granted" : "Screen capture missing", systemImage: controller.screenCaptureAuthorized ? "checkmark.circle.fill" : "xmark.circle")
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
                    if !controller.latestLiveTranscriptText.isEmpty || !controller.latestLiveTranslationText.isEmpty {
                        CopyableTextSection(title: "Live Transcript", text: controller.latestLiveTranscriptText, minHeight: 70)
                        CopyableTextSection(title: "Live Translation", text: controller.latestLiveTranslationText, minHeight: 70)
                    }
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

    /// Counts seconds elapsed while in .loading state — updated by an async task.
    @State private var loadingElapsed: Int = 0

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
            if case .downloading(let fraction) = state {
                ProgressView(value: fraction > 0 ? fraction : nil)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)
                if label == "Qwen" {
                    Text("Первая загрузка — модель скачивается (~0.5–2 GB). В следующий раз будет быстро.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 200, alignment: .leading)
                }
            } else if state == .loading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)
                Text("Загрузка из кэша в память…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if state == .processing {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)
            }
        }
        // Async ticker: increments loadingElapsed every second while in .loading state.
        // The task is automatically cancelled when isLoading flips to false.
        .task(id: isLoading) {
            guard isLoading else { return }
            loadingElapsed = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                loadingElapsed += 1
            }
        }
    }

    private var isLoading: Bool { state == .loading }

    private var stateLabel: String {
        switch state {
        case .idle:             return "idle"
        case .loading:          return "loading… \(loadingElapsed)s"
        case .processing:       return label == "Whisper" ? "transcribing…" : "rewriting…"
        case .downloading(let f):
            return f > 0.001 ? "downloading \(Int(f * 100))%" : "downloading…"
        case .ready:            return "ready"
        case .failed:           return "failed"
        case .disabled:         return "disabled"
        }
    }
}
