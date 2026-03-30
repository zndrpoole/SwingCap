import Foundation

/// Utilities for managing clip files on disk.
enum ClipStorageManager {

    static let clipsDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("SwingCap/Clips", isDirectory: true)
    }()

    /// Deletes MP4 files in the clips directory that have no matching filename
    /// in `knownFileNames`. Safe to call at any time; errors are silently ignored.
    static func deleteOrphanedFiles(knownFileNames: Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: clipsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in contents where url.pathExtension == "mp4" {
            if !knownFileNames.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Total size in bytes of all files in the clips directory.
    static func totalStorageBytes() -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: clipsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        return contents.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }

    /// Human-readable storage string, e.g. "142 MB".
    static func formattedStorageSize() -> String {
        ByteCountFormatter.string(
            fromByteCount: totalStorageBytes(),
            countStyle: .file
        )
    }
}
