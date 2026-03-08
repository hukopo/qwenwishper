import AppKit
import ApplicationServices
import Foundation

struct PasteService: TextInjector {
    func insert(text: String) throws -> InsertResult {
        if try insertViaAccessibility(text) {
            return InsertResult(method: .accessibility)
        }

        try insertViaClipboard(text)
        return InsertResult(method: .clipboardFallback)
    }

    private func insertViaAccessibility(_ text: String) throws -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObject)
        guard focusedStatus == .success, let focusedObject else {
            return false
        }

        let focusedElement = focusedObject as! AXUIElement

        var valueObject: CFTypeRef?
        var rangeObject: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &valueObject)
        let rangeStatus = AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeObject)

        guard valueStatus == .success, rangeStatus == .success, let currentValue = valueObject as? String, let rangeValue = rangeObject else {
            return false
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            return false
        }

        let nsValue = currentValue as NSString
        let replacementRange = NSRange(location: range.location, length: range.length)
        guard replacementRange.location != NSNotFound, replacementRange.location <= nsValue.length else {
            return false
        }

        let updated = nsValue.replacingCharacters(in: replacementRange, with: text)
        let setValueStatus = AXUIElementSetAttributeValue(focusedElement, kAXValueAttribute as CFString, updated as CFTypeRef)
        guard setValueStatus == .success else {
            return false
        }

        var newRange = CFRange(location: replacementRange.location + (text as NSString).length, length: 0)
        if let newRangeValue = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, newRangeValue)
        }

        return true
    }

    private func insertViaClipboard(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        let originalItems = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data] in
            var snapshot: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot[type] = data
                }
            }
            return snapshot
        } ?? []

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw AppFailure.pasteFailed("Unable to write text to the clipboard.")
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw AppFailure.pasteFailed("Unable to create CGEventSource.")
        }

        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        commandDown?.flags = .maskCommand
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        commandUp?.flags = .maskCommand
        commandDown?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if originalItems.isEmpty {
                return
            }

            pasteboard.clearContents()
            for snapshot in originalItems {
                let item = NSPasteboardItem()
                for (type, data) in snapshot {
                    item.setData(data, forType: type)
                }
                pasteboard.writeObjects([item])
            }
        }
    }
}
