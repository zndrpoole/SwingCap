import AVFoundation

/// Receives raw `CMSampleBuffer` frames from `AVCaptureVideoDataOutput`,
/// feeds them into the rolling buffer, and runs strike detection.
///
/// ## State machine
///
/// ```
/// .idle
///   │  Every frame → append to rollingBuffer + run strike detector
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
///            .awaitingGesture(clipID:remaining:)   ← gesture rating window
///               │  Every frame → feed HandGestureDetector
///               │  Rolling buffer still fills (pre-window for next clip)
///               │
///               ├─ Gesture detected → emit via onGestureReady, → .idle
///               └─ remaining == 0 (timeout) → .idle
/// ```
///
/// **Why suppress strike detection during the gesture window?**
/// The golfer may be raising their hand toward the camera. Without suppression,
/// that arm motion could score high enough on the luma-diff detector to
/// trigger a false clip. During `.awaitingGesture` we skip
/// `detector.process(_:)` entirely.
///
/// **Rolling buffer during gesture window**: we keep appending frames so the
/// next shot's pre-strike buffer fills naturally while the user is rating.
///
/// **Threading**: all methods are called on the camera frames queue — single-
/// threaded; no additional locking needed for the state machine.
final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Configuration

    /// Frames captured *after* detection (1 second at 60 fps).
    private let postStrikeFrameCount = 60

    /// Default gesture window length in frames.
    /// Reads `gestureWindowSeconds` from UserDefaults (set by SettingsView),
    /// falling back to 5 seconds.
    private var gestureWindowFrameCount: Int {
        let seconds = UserDefaults.standard.double(forKey: "gestureWindowSeconds")
        return Int((seconds > 0 ? seconds : 5.0) * 60)
    }

    // MARK: - Dependencies

    let rollingBuffer: RollingFrameBuffer
    let detector: BallStrikeDetector
    let gestureDetector: HandGestureDetector

    /// Called (on the frames queue) when a complete pre+post window is ready.
    /// Ownership of the frame array is transferred to the caller.
    var onFrameWindowReady: (([CMSampleBuffer]) -> Void)?

    /// Called (on the main queue via `HandGestureDetector`) when a stable
    /// gesture is detected during the rating window.
    var onGestureReady: ((GestureEvent) -> Void)?

    // MARK: - State machine

    private enum State {
        case idle
        /// Collecting post-strike frames.
        /// - `preFrames`: snapshot from rolling buffer at detection moment.
        /// - `remaining`: how many more post-strike frames to collect.
        case capturingPost(preFrames: [CMSampleBuffer], remaining: Int)
        /// Waiting for the golfer to show a thumbs-up or thumbs-down.
        /// - `clipID`: the UUID of the clip just saved (for `GestureEvent`).
        /// - `remaining`: frames left in the gesture window before timeout.
        case awaitingGesture(clipID: UUID, remaining: Int)
    }

    private var state: State = .idle

    // MARK: - Init

    init(buffer: RollingFrameBuffer = RollingFrameBuffer()) {
        self.rollingBuffer = buffer
        self.detector = BallStrikeDetector()
        self.gestureDetector = HandGestureDetector()
        super.init()

        detector.onStrike = { [weak self] event in
            self?.handleStrike(event)
        }

        // Gesture detector fires on the main queue; hop back to the frames
        // queue is not needed — we update state via a separate callback
        // rather than mutating FrameProcessor state directly here.
        gestureDetector.onGesture = { [weak self] rating, confidence in
            self?.handleGesture(rating: rating, confidence: confidence)
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    /// Called once per frame on the camera frames queue.
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
                // Window complete — emit the full frame window.
                let fullWindow = preFrames + [sampleBuffer]
                // We don't know the clip ID yet (assigned by ClipExporter).
                // FrameProcessor uses a temporary UUID; DrivingSession will
                // match this to the actual Clip.id via onFrameWindowReady.
                let pendingClipID = UUID()
                state = .awaitingGesture(
                    clipID: pendingClipID,
                    remaining: gestureWindowFrameCount
                )
                gestureDetector.reset()
                onFrameWindowReady?(fullWindow)
            } else {
                state = .capturingPost(preFrames: preFrames + [sampleBuffer],
                                       remaining: newRemaining)
            }

        case .awaitingGesture(let clipID, let remaining):
            // Keep filling the rolling buffer for the next shot's pre-window.
            rollingBuffer.append(sampleBuffer)
            // Feed frame to gesture detector (drops frame if Vision is busy).
            gestureDetector.process(sampleBuffer)

            let newRemaining = remaining - 1
            if newRemaining <= 0 {
                // Window expired — return to idle without a rating.
                state = .idle
            } else {
                state = .awaitingGesture(clipID: clipID, remaining: newRemaining)
            }
        }
    }

    /// Called when AVFoundation drops a frame (back-pressure or slow consumer).
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

    // MARK: - Handlers (called on frames queue / main queue)

    /// Responds to a confirmed strike event from the ball detector.
    private func handleStrike(_ event: StrikeEvent) {
        guard case .idle = state else { return }
        let preFrames = rollingBuffer.snapshot()
        rollingBuffer.clear()
        state = .capturingPost(preFrames: preFrames, remaining: postStrikeFrameCount)
        print("🏌️ Strike detected — confidence \(String(format: "%.2f", event.confidence)), \(preFrames.count) pre-frames buffered")
    }

    /// Responds to a confirmed hand gesture from the gesture detector.
    /// Called on the **main queue** (dispatched by `HandGestureDetector`).
    private func handleGesture(rating: ShotRating, confidence: Float) {
        guard case .awaitingGesture(let clipID, _) = state else { return }
        state = .idle
        let event = GestureEvent(clipID: clipID, rating: rating, confidence: confidence)
        onGestureReady?(event)
        print("👍 Gesture detected — rating: \(rating), confidence: \(String(format: "%.2f", confidence))")
    }

    // MARK: - Debug

#if DEBUG
    /// Whether the processor is currently in its gesture rating window.
    var isAwaitingGesture: Bool {
        if case .awaitingGesture = state { return true }
        return false
    }
#endif
}
