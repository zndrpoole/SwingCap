import AVFoundation

/// Common interface for all strike-detection strategies.
/// `BallStrikeDetector` routes to a concrete implementation at runtime.
protocol StrikeDetectorProtocol: AnyObject {
    /// Called on the camera frames queue when a strike is detected.
    var onStrike: ((StrikeEvent) -> Void)? { get set }
    /// Process one camera frame. Must return quickly; heavy work dispatches async.
    func process(_ sampleBuffer: CMSampleBuffer)
#if DEBUG
    /// Most-recent raw detection score (motion score or ML confidence).
    var lastScore: Float { get }
#endif
}
