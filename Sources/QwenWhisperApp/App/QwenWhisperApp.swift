import AppKit
import SwiftUI

@main
struct QwenWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("QwenWhisper", systemImage: controller.status.systemImage) {
            MenuBarContentView(controller: controller)
                .frame(width: 360)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(controller: controller)
        }

        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsView(controller: controller)
                .frame(minWidth: 540, minHeight: 420)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
