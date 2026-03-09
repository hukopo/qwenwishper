import AppKit
import Combine
import SwiftUI

@MainActor
final class PanelState: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var resultText: String? = nil
    @Published var isCopied: Bool = false
}

/// Manages a borderless floating NSPanel that shows pipeline status above all windows.
@MainActor
final class FloatingStatusPanel {
    private var panel: NSPanel?
    let state = PanelState()
    private var cancellables = Set<AnyCancellable>()
    private var currentStatus: PipelineStatus = .idle
    private var resultHideTask: Task<Void, Never>?

    func setup(controller: AppController) {
        let contentView = FloatingStatusView(controller: controller, state: state) { [weak controller] in
            controller?.dismissError()
        }
        let hosting = NSHostingView(rootView: contentView)

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 80, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false

        self.panel = panel

        controller.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateForStatus(status)
            }
            .store(in: &cancellables)

        controller.$lastSnapshot
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                let text = snapshot.rewrittenText.isEmpty ? snapshot.sourceText : snapshot.rewrittenText
                guard !text.isEmpty else { return }
                self?.showResult(text)
            }
            .store(in: &cancellables)

        state.$isCopied
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    self?.dismissResult()
                }
            }
            .store(in: &cancellables)
    }

    private func updateForStatus(_ status: PipelineStatus) {
        currentStatus = status
        guard state.resultText == nil else { return }
        switch status {
        case .recording, .transcribing, .rewriting, .pasting, .error:
            show()
        case .idle, .checkingPermissions, .loadingModels:
            hide()
        }
    }

    private func showResult(_ text: String) {
        resultHideTask?.cancel()
        state.isCopied = false
        state.resultText = text
        show()
        resultHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            self.dismissResult()
        }
    }

    private func dismissResult() {
        resultHideTask?.cancel()
        resultHideTask = nil
        state.resultText = nil
        state.isCopied = false
        updateForStatus(currentStatus)
    }

    private func show() {
        guard let panel else { return }
        if !panel.isVisible {
            positionPanel(panel)
            state.isVisible = false
            panel.orderFront(nil)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(16))
                self.state.isVisible = true
            }
        } else {
            positionPanel(panel)
            state.isVisible = true
        }
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let fitting = panel.contentView?.fittingSize ?? CGSize(width: 80, height: 44)
        let x = screenFrame.midX - fitting.width / 2
        let y = screenFrame.minY + 24
        panel.setFrame(CGRect(origin: CGPoint(x: x, y: y), size: fitting), display: true)
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        state.isVisible = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(230))
            guard !self.state.isVisible else { return }
            self.panel?.orderOut(nil)
        }
    }
}
