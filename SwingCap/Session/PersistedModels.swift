import Foundation
import SwiftData
import UIKit

/// SwiftData model for a single saved swing clip.
///
/// Stores only serialisable primitives — `UIImage` is JPEG-encoded to `Data`
/// so it can be stored in SwiftData without a custom transformer.
///
/// ## Filename vs. URL
/// Only the filename is stored (e.g. `"ABC123.mp4"`), not the full path.
/// This lets clips survive app reinstalls or iCloud restore where the
/// Documents directory path changes. `toClip()` reconstructs the full URL
/// by appending the filename to the current Documents directory at read time.
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
    /// Optional user note attached to this clip. Empty string by default.
    var notes: String
    /// Raw string backing for `ShotRating` (`"good"`, `"bad"`, or `nil` = unrated).
    /// Stored as a raw String rather than an enum so SwiftData doesn't need a
    /// custom transformer and the model remains forward-compatible.
    var ratingRawValue: String?

    /// Typed accessor over `ratingRawValue`.
    var rating: ShotRating? {
        get { ratingRawValue.flatMap { ShotRating(rawValue: $0) } }
        set { ratingRawValue = newValue?.rawValue }
    }

    /// Creates a new `PersistedClip` from a freshly exported `Clip` value.
    init(from clip: Clip) {
        self.id = clip.id
        self.fileName = clip.url.lastPathComponent
        self.createdAt = clip.createdAt
        self.thumbnailData = clip.thumbnail?.jpegData(compressionQuality: 0.7)
        self.duration = clip.duration
        self.notes = ""
        self.ratingRawValue = clip.rating?.rawValue
    }

    /// Reconstructs a `Clip` value for use in SwiftUI views.
    /// The URL is rebuilt from the current Documents directory, not stored.
    func toClip() -> Clip {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("SwingCap/Clips/\(fileName)")
        let thumbnail = thumbnailData.flatMap { UIImage(data: $0) }
        return Clip(id: id, url: url, createdAt: createdAt, thumbnail: thumbnail,
                    duration: duration, rating: rating)
    }
}

/// SwiftData model for one driving-range session.
///
/// The `@Relationship(deleteRule: .cascade)` on `clips` means deleting a
/// `PersistedSession` automatically deletes all its `PersistedClip` records —
/// no manual cleanup needed in `SessionStore.delete(_:)`.
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

    /// Convenience: total clip count for display in `SessionHistoryView`.
    var clipCount: Int { clips.count }

    /// SwiftData relationship order is not guaranteed, so we sort by `createdAt`
    /// to ensure clips always appear chronologically in the player and grid.
    var orderedClips: [PersistedClip] {
        clips.sorted { $0.createdAt < $1.createdAt }
    }
}
