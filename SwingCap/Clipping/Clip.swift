import Foundation
import UIKit

/// An immutable value representing a saved swing clip.
///
/// `Clip` is passed throughout the app as a lightweight value type. The actual
/// video data lives on disk at `url`; `Clip` just holds the metadata needed to
/// display thumbnails, play back the video, and persist the record to SwiftData.
///
/// `Sendable` conformance allows `Clip` to be safely passed across actor
/// boundaries — e.g. from `ClipExporter` (actor) back to `DrivingSession`
/// (@Observable on the main actor).
struct Clip: Identifiable, Sendable {
    let id: UUID
    /// Location of the MP4 file in the app's Documents directory.
    /// Always within `SwingCap/Clips/` — never the Photos library.
    let url: URL
    let createdAt: Date
    /// Representative frame extracted from the middle of the clip.
    /// `nil` if thumbnail generation failed (rare; the grid shows a fallback icon).
    let thumbnail: UIImage?
    /// Clip length in seconds, derived from the PTS spread of the first and
    /// last frames rather than the encoded container duration.
    let duration: TimeInterval
    /// User's subjective rating, set via hand gesture or manual tap.
    /// `nil` means the clip has not been rated yet.
    let rating: ShotRating?

    /// Designated initialiser for newly created clips (generates a fresh UUID).
    init(url: URL, thumbnail: UIImage? = nil, duration: TimeInterval) {
        self.id = UUID()
        self.url = url
        self.createdAt = Date()
        self.thumbnail = thumbnail
        self.duration = duration
        self.rating = nil
    }

    /// Memberwise initialiser used when reconstructing a `Clip` from persisted
    /// data — preserves the original `id`, `createdAt`, and `rating`.
    init(id: UUID, url: URL, createdAt: Date, thumbnail: UIImage?,
         duration: TimeInterval, rating: ShotRating? = nil) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.thumbnail = thumbnail
        self.duration = duration
        self.rating = rating
    }

    /// Returns a copy of this clip with the given rating applied.
    /// Used by `DrivingSession` to update an existing clip non-mutably.
    func withRating(_ newRating: ShotRating?) -> Clip {
        Clip(id: id, url: url, createdAt: createdAt, thumbnail: thumbnail,
             duration: duration, rating: newRating)
    }
}
