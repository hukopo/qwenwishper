import AppKit
import ApplicationServices
import AVFoundation
import Foundation

final class PermissionManager: PermissionManaging, @unchecked Sendable {
    func currentMicrophonePermission() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func ensureMicrophoneAccess() async -> Bool {
        switch currentMicrophonePermission() {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }

    func isScreenCaptureAuthorized() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenCaptureAccess() async -> Bool {
        if isScreenCaptureAuthorized() {
            return true
        }
        if CGRequestScreenCaptureAccess() {
            return true
        }
        // macOS shows the prompt only once per app; afterwards the request silently returns false.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
