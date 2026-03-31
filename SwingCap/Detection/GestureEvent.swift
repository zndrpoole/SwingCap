import Foundation

/// The user's subjective rating of a shot, captured via hand gesture.
enum ShotRating: String, Codable {
    case good
    case bad
}

/// A confirmed hand gesture event emitted by `HandGestureDetector`.
///
/// `clipID` ties the rating back to the specific clip that was just saved,
/// allowing `DrivingSession` to find and update the correct `Clip` even if
/// multiple clips exist in the session.
struct GestureEvent {
    /// The ID of the clip this rating applies to.
    let clipID: UUID
    let rating: ShotRating
    /// Normalised confidence in [0, 1] based on the proportion of stable
    /// frames that agreed on the gesture within the hold window.
    let confidence: Float
}
