import AppKit
import SwiftUI

struct CopyableTextSection: View {
    let title: String
    let text: String
    var font: Font = .caption
    var minHeight: CGFloat = 80

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Copy") {
                        copyToPasteboard(text)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(text.isEmpty)
                }

                ScrollView {
                    Text(text.isEmpty ? "No data yet." : text)
                        .font(font)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
