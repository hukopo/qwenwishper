import Foundation

@MainActor
final class AppLogger {
    private(set) var entries: [DiagnosticsEntry] = []
    private let maxEntries = 200

    func info(_ message: String) {
        append(.init(level: .info, message: message))
    }

    func warning(_ message: String) {
        append(.init(level: .warning, message: message))
    }

    func error(_ message: String) {
        append(.init(level: .error, message: message))
    }

    private func append(_ entry: DiagnosticsEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        DiagnosticTrace.write("\(entry.level.rawValue.uppercased()): \(entry.message)")
    }
}
