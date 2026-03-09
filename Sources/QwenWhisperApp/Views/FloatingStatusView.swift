import AppKit
import SwiftUI

struct FloatingStatusView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var state: PanelState
    let onErrorTapped: () -> Void

    @State private var barLevels: [Float] = [0.15, 0.25, 0.2, 0.3, 0.15]

    var body: some View {
        mainContent
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(pillBackground)
            .onTapGesture {
                if case .error = controller.status { onErrorTapped() }
            }
            .scaleEffect(x: 1, y: state.isVisible ? 1 : 0.01, anchor: .center)
            .opacity(state.isVisible ? 1 : 0)
            .animation(.spring(duration: 0.2, bounce: 0.1), value: state.isVisible)
            .task(id: controller.status == .recording) {
                guard controller.status == .recording else { return }
                while !Task.isCancelled {
                    let rawLevel = controller.audioLevel
                    let normalized = Float(max(0, min(1, Double((rawLevel + 50) / 50))))
                    barLevels = (0 ..< 5).map { _ in
                        max(0.06, min(1.0, normalized + Float.random(in: -0.3 ... 0.3)))
                    }
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let resultText = state.resultText {
            resultView(resultText)
        } else {
            pipelineContent
        }
    }

    private func resultView(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(width: 190, alignment: .leading)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                state.isCopied = true
            } label: {
                Image(systemName: state.isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.isCopied ? Color.green : .white)
                    .frame(width: 20, height: 20)
                    .animation(.easeInOut(duration: 0.15), value: state.isCopied)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var pipelineContent: some View {
        switch controller.status {
        case .recording:
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0 ..< 5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white)
                        .frame(width: 3, height: max(3, CGFloat(barLevels[i]) * 20))
                        .animation(.easeInOut(duration: 0.1), value: barLevels[i])
                }
            }
            .frame(width: 27, height: 20)
        case .transcribing, .pasting:
            ProgressView()
                .tint(.white)
                .scaleEffect(0.8)
                .frame(width: 18, height: 18)
        case .rewriting:
            ProgressView()
                .tint(.white)
                .scaleEffect(0.8)
                .frame(width: 18, height: 18)
        case .error:
            Image(systemName: "exclamationmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
        default:
            Color.clear
                .frame(width: 18, height: 18)
        }
    }

    private var pillBackground: some View {
        let (bg, border) = pillColors
        return RoundedRectangle(cornerRadius: 12)
            .fill(bg)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(border, lineWidth: 1.5)
            )
            .shadow(color: border.opacity(0.5), radius: 6)
            .animation(.easeInOut(duration: 0.3), value: state.resultText != nil)
    }

    private var pillColors: (Color, Color) {
        if state.resultText != nil {
            return (.black.opacity(0.85), Color.white.opacity(0.35))
        }
        switch controller.status {
        case .error:
            return (.red.opacity(0.9), .red)
        case .rewriting:
            return (.black.opacity(0.85), Color(red: 0.6, green: 0.1, blue: 0.95))
        default:
            return (.black.opacity(0.85), .white.opacity(0.25))
        }
    }
}
