import AppKit
import Foundation

struct StorageSnapshot: Sendable {
    let appURL: URL
    let appSizeBytes: Int64
    let modelsURL: URL
    let modelsSizeBytes: Int64
    let recordingsURL: URL
    let recordingsSizeBytes: Int64
}

enum StorageService {
    static func makeModelsURL() -> URL {
        cacheBase().appendingPathComponent("Models")
    }

    static func makeRecordingsURL() -> URL {
        cacheBase().appendingPathComponent("Recordings")
    }

    static func snapshot() async -> StorageSnapshot {
        await Task.detached(priority: .utility) {
            let appURL = Bundle.main.bundleURL
            let modelsURL = makeModelsURL()
            let recordingsURL = makeRecordingsURL()
            return StorageSnapshot(
                appURL: appURL,
                appSizeBytes: directorySize(at: appURL),
                modelsURL: modelsURL,
                modelsSizeBytes: directorySize(at: modelsURL),
                recordingsURL: recordingsURL,
                recordingsSizeBytes: directorySize(at: recordingsURL)
            )
        }.value
    }

    static func openModelsFolder() {
        let url = makeModelsURL()
        ensureDirectory(at: url)
        NSWorkspace.shared.open(url)
    }

    static func openRecordingsFolder() {
        let url = makeRecordingsURL()
        ensureDirectory(at: url)
        NSWorkspace.shared.open(url)
    }

    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    static func clearRecordings() async throws {
        let url = makeRecordingsURL()
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        for file in contents where file.pathExtension == "caf" {
            try fm.removeItem(at: file)
        }
    }

    private static func cacheBase() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QwenWhisper")
    }

    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        var total: Int64 = 0
        let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private static func ensureDirectory(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

extension Int64 {
    var humanReadableFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
