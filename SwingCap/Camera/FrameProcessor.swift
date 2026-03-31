import AVFoundation

/// Receives raw `CMSampleBuffer` frames from `AVCaptureVideoDataOutput`,
/// feeds them into the rolling buffer, and runs strike detection.
///
/// ## State machine
///
/// ```
/// .idle
///   │  Every frame → append to rollingBuffer + run detector
///   │
///   └─ Strike detected
///         │  Snapshot rollingBuffer (pre-strike frames)
///         │  Clear rollingBuffer
///         ↓
///      .capturingPost(preFrames:remaining:)
///         │  Every frame → append to preFrames array, decrement remaining
///         │
///         └─ remaining == 0
///               │  Emit full window (pre + post) via onFrameWindowReady
///               ↓
///            .idle
/// ```
///
/// **Why clear the rolling buffer on strike?** To prevent a second close-in
/// detection from grabbing frames that are already part of the first clip's
/// post-window. The buffer refills naturally once we return to `.idle`.
///
/// **Threading**: All methods are called on the camera frames queue — the
/// single serial queue set up by `CameraSession.rebindDelegate()`. The state
/// machine is therefore single-threaded and needs no additional locking.
final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Configuration

    /// Frames captured *after* detection (1 second at 60 fps).
    private let postStrikeFrameCount = 60

    // MARK: - Dependencies

    let rollingBuffer: RollingFrameBuffer
    let detector: BallStrikeDetector

    /// Called (on the frames queue) when a complete pre+post window is ready.
    /// Ownership of the frame array is transferred to the caller; they are
    /// responsible for passing it on to `ClipExporter` and releasing it.
    var onFrameWindowReady: (([CMSampleBuffer]) -> Void)?

    // MARK: - State machine

    private enum State {
        case idle
        /// Collecting post-strike frames.
        /// - `preFrames`: snapshot from rolling buffer at detection moment.
        /// - `remaining`: how many more post-strike frames to collect before
        ///   the window is complete and `onFrameWindowReady` fires.
        case capturingPost(preFrames: [CMSampleBuffer], remaining: Int)
    }

    private var state: State = .idle

    // MARK: - Init

    init(buffer: RollingFrameBuffer = RollingFrameBuffer()) {
        self.rollingBuffer = buffer
        self.detector = BallStrikeDetector()
        super.init()

        // Wire the detector's output back into this processor's state machine.
        detector.onStrike = { [weak self] event in
            self?.handleStrike(event)
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    /// Called once per frame on the camera frames queue.
    ///
    /// In `.idle`:  feed the frame into both the rolling buffer and detector.
    /// In `.capturingPost`:  accumulate post-strike frames until the window
    ///                       is full, then fire `onFrameWindowReady` and reset.
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        switch state {
        case .idle:
            rollingBuffer.append(sampleBuffer)
            detector.process(sampleBuffer)

        case .capturingPost(let preFrames, let remaining):
            let newRemaining = remaining - 1
            if newRemaining <= 0 {
                // Window complete — emit and reset to idle.
                // The full window is preFrames (up to 120) + this final frame.
                let fullWindow = preFrames + [sampleBuffer]
                state = .idle
                onFrameWindowReady?(fullWindow)
            } else {
                // Keep accumulating post-strike frames.
                state = .capturingPost(preFrames: preFrames + [sampleBuffer],
                                       remaining: newRemaining)
            }
        }
    }

    /// Called when AVFoundation drops a frame (typically due to backpressure).
    /// In production a drop during post-capture shortens the clip slightly;
    /// in DEBUG we print the reason to help diagnose pipeline pressure.
    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
#if DEBUG
        let reason = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_DroppedFrameReason,
            attachmentModeOut: nil
        )
        print("⚠️ Frame dropped — reason: \(reason ?? "unknown" as CFTypeRef)")
#endif
    }

    // MARK: - Strike handler (called on frames queue)

    /// Responds to a confirmed strike event from the detector.
    /// Ignored if we are already in `capturingPost` (i.e. a second swing
    /// happens before the first clip's post-window finishes).
    private func handleStrike(_ event: StrikeEvent) {
        guard case .idle = state else { return }

        // Take everything the rolling buffer has collected so far as the
        // pre-strike window, then clear it so fresh frames refill cleanly.
        let preFrames = rollingBuffer.snapshot()
        rollingBuffer.clear()
        state = .capturingPost(preFrames: preFrames, remaining: postStrikeFrameCount)
        print("🏌️ Strike detected — confidence \(String(format: "%.2f", event.confidence)), \(preFrames.count) pre-frames buffered")
    }
}
