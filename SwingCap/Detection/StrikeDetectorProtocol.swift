import AVFoundation

/// Common interface for all strike-detection strategies.
///
/// `BallStrikeDetector` holds a reference to one concrete implementation at a
/// time and routes all calls through this protocol. The two implementations are:
/// - `MotionThresholdDetector` — luma-diff based, available immediately.
/// - `CoreMLBallDetector` — YOLO model, loaded asynchronously after app launch.
///
/// Adding a new strategy only requires conforming to this protocol and
/// teaching `BallStrikeDetector.init()` when to use it.
protocol StrikeDetectorProtocol: AnyObject {

    /// Called on the camera frames queue when a strike is detected.
    /// Implementations must set this before `process` is called.
    var onStrike: ((StrikeEvent) -> Void)? { get set }

    /// Processes one camera frame. Must return quickly so the 60fps pipeline
    /// is not stalled — heavy work (e.g. Vision inference) must dispatch async.
    func process(_ sampleBuffer: CMSampleBuffer)

#if DEBUG
    /// Most-recent raw detection score (motion score or ML confidence).
    /// Exposed only in DEBUG builds for the `DebugOverlayView`.
    var lastScore: Float { get }
#endif
}
