import CoreMedia

/// A detected golf ball impact event emitted by the strike detector.
struct StrikeEvent {
    /// Presentation timestamp of the frame that triggered detection.
    let timestamp: CMTime
    /// Normalised confidence in [0, 1]. For the motion-threshold detector
    /// this is a scaled motion score; for Core ML it will be model confidence.
    let confidence: Float
}
