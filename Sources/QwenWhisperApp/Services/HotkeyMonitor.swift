import Carbon
import Foundation

final class HotkeyMonitor: HotkeyMonitoring {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var hotKeyID = EventHotKeyID(signature: OSType(0x51574850), id: 1)

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(_ descriptor: HotkeyDescriptor) throws {
        unregister()

        let status = RegisterEventHotKey(
            UInt32(descriptor.keyCode),
            descriptor.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            throw AppFailure.pasteFailed("Unable to register the global hotkey.")
        }

        var eventTypeSpecs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )

            guard hkID.id == monitor.hotKeyID.id else { return noErr }
            let kind = GetEventKind(eventRef)
            if kind == UInt32(kEventHotKeyPressed) {
                monitor.onPress?()
            } else if kind == UInt32(kEventHotKeyReleased) {
                monitor.onRelease?()
            }
            return noErr
        }

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            eventTypeSpecs.count,
            &eventTypeSpecs,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )

        guard handlerStatus == noErr else {
            unregister()
            throw AppFailure.pasteFailed("Unable to install the hotkey event handler.")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
