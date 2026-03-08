import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Diagnostics")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("Refresh Permissions") {
                        controller.refreshPermissions(promptForAccessibility: false)
                    }
                }

                CopyableTextSection(
                    title: "After Whisper",
                    text: controller.latestWhisperText,
                    font: .body,
                    minHeight: 110
                )

                CopyableTextSection(
                    title: "After Qwen",
                    text: controller.latestQwenText,
                    font: .body,
                    minHeight: 110
                )

                if let snapshot = controller.lastSnapshot {
                    GroupBox("Last Insert") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Finished at \(snapshot.finishedAt.formatted(date: .abbreviated, time: .standard))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Method: \(snapshot.insertMethod.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                CopyableTextSection(
                    title: "Logs",
                    text: controller.diagnosticsText,
                    font: .caption.monospaced(),
                    minHeight: 240
                )
            }
        }
        .padding(16)
    }
}
