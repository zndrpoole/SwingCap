import Foundation
import SwiftData
import UIKit

/// SwiftData model for a single saved swing clip.
/// Stores only serialisable primitives; `UIImage` is encoded as JPEG `Data`.
@Model
final class PersistedClip {
    var id: UUID
    /// Filename only (e.g. "ABC123.mp4") — reconstructed against the clips
    /// directory at load time so the model survives app reinstalls.
    var fileName: String
    var createdAt: Date
    /// JPEG-compressed thumbnail (~50–150 KB each).
    var thumbnailData: Data?
    var duration: TimeInterval

    init(from clip: Clip) {
        self.id = clip.id
        self.fileName = clip.url.lastPathComponent
        self.createdAt = clip.createdAt
        self.thumbnailData = clip.thumbnail?.jpegData(compressionQuality: 0.7)
        self.duration = clip.duration
    }

    func toClip() -> Clip {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("SwingCap/Clips/\(fileName)")
        let thumbnail = thumbnailData.flatMap { UIImage(data: $0) }
        return Clip(id: id, url: url, createdAt: createdAt, thumbnail: thumbnail, duration: duration)
    }
}

/// SwiftData model for one driving-range session.
@Model
final class PersistedSession: Identifiable {
    var id: UUID
    var startedAt: Date
    @Relationship(deleteRule: .cascade) var clips: [PersistedClip]

    init(startedAt: Date = Date()) {
        self.id = UUID()
        self.startedAt = startedAt
        self.clips = []
    }

    /// Convenience: total clip count.
    var clipCount: Int { clips.count }

    /// Ordered clips (SwiftData relationship order is not guaranteed).
    var orderedClips: [PersistedClip] {
        clips.sorted { $0.createdAt < $1.createdAt }
    }
}
