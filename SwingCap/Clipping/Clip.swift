import Foundation
import UIKit

/// An immutable value representing a saved swing clip.
struct Clip: Identifiable, Sendable {
    let id: UUID
    /// Location of the MP4 file in the app's Documents directory.
    let url: URL
    let createdAt: Date
    /// Representative frame extracted from the middle of the clip.
    let thumbnail: UIImage?
    /// Clip length in seconds (derived from frame timestamps).
    let duration: TimeInterval

    init(url: URL, thumbnail: UIImage? = nil, duration: TimeInterval) {
        self.id = UUID()
        self.url = url
        self.createdAt = Date()
        self.thumbnail = thumbnail
        self.duration = duration
    }
}
