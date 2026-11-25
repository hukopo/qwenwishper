import AppKit
import SwiftUI

@main
struct QwenWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AppController()

    var body: some Scene {
        // Fixed icon on purpose: progress is shown by the floating pill, not the menu bar.
        MenuBarExtra {
            MenuBarContentView(controller: controller)
                .frame(width: 360)
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        // ponytail: plain Window instead of Settings scene — openSettings() is unreliable from an accessory MenuBarExtra.
        Window("QwenWhisper Settings", id: "settings") {
            SettingsView(controller: controller)
        }

        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsView(controller: controller)
                .frame(minWidth: 540, minHeight: 420)
        }
    }
}

extension QwenWhisperApp {
    /// Qwen-style hexagon around a microphone; template image, so macOS tints it for light/dark menu bars.
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 8.2
            let hexagon = NSBezierPath()
            for i in 0 ..< 6 {
                let angle = CGFloat.pi / 2 + CGFloat(i) * .pi / 3
                let point = NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                i == 0 ? hexagon.move(to: point) : hexagon.line(to: point)
            }
            hexagon.close()
            hexagon.lineWidth = 1.5
            hexagon.lineJoinStyle = .round
            NSColor.black.setStroke()
            hexagon.stroke()

            let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let size = mic.size
                mic.draw(in: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "QwenWhisper"
        return image
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
