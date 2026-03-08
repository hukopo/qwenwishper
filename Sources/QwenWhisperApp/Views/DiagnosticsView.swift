import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Refresh Permissions") {
                    controller.refreshPermissions(promptForAccessibility: false)
                }
            }

            List(controller.diagnostics) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.message)
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot = controller.lastSnapshot {
                GroupBox("Last Insert") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.rewrittenText)
                        Text("Finished at \(snapshot.finishedAt.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
    }
}
