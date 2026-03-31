import Foundation

/// Utilities for managing clip files on disk.
///
/// All clip MP4 files live in `Documents/SwingCap/Clips/`. This enum provides
/// helpers to calculate storage usage and remove orphaned files (files that
/// exist on disk but have no corresponding `PersistedClip` SwiftData record).
///
/// Orphaned files can accumulate if the app crashes after writing a clip file
/// but before the SwiftData record is committed. `SessionStore` calls
/// `deleteOrphanedFiles` once at init to clean these up.
enum ClipStorageManager {

    static let clipsDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("SwingCap/Clips", isDirectory: true)
    }()

    /// Deletes MP4 files in the clips directory whose filename is not in
    /// `knownFileNames`. Safe to call at any time; any file I/O errors are
    /// silently ignored so a single bad file doesn't block cleanup of the rest.
    ///
    /// - Parameter knownFileNames: A set of bare filenames (e.g. `"ABC123.mp4"`)
    ///   that are referenced by a `PersistedClip` record. Everything else is deleted.
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
    /// Used by `SettingsView` to display storage consumption.
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
