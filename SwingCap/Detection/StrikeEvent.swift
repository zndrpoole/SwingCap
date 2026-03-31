import CoreMedia

/// A detected golf ball impact event emitted by the active `StrikeDetectorProtocol`.
///
/// `FrameProcessor` receives this via the `onStrike` callback and transitions
/// from `.idle` to `.capturingPost` — the event itself is not stored long-term.
struct StrikeEvent {
    /// Presentation timestamp of the frame that triggered detection.
    /// Used by detectors to enforce the cooldown period between events.
    let timestamp: CMTime
    /// Normalised confidence in [0, 1].
    /// - `MotionThresholdDetector`: linearly scaled from the motion score
    ///   (score / threshold × 0.5, capped at 1.0).
    /// - `CoreMLBallDetector`: fixed at 0.9 when the departure threshold is met,
    ///   since the model's per-class confidence is already filtered upstream.
    let confidence: Float
}
