import AVFoundation

/// Receives raw `CMSampleBuffer` frames from `AVCaptureVideoDataOutput`,
/// feeds them into the rolling buffer, and runs strike detection.
///
/// On a confirmed strike the processor switches into a post-strike capture
/// window, collects `postStrikeFrameCount` additional frames, then emits
/// the full window (pre + post) via `onFrameWindowReady`.
///
/// All methods are called on the camera frames queue — no additional locking
/// is needed for the state machine.
final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Configuration

    /// Frames captured *after* detection (1 second at 60 fps).
    private let postStrikeFrameCount = 60

    // MARK: - Dependencies

    let rollingBuffer: RollingFrameBuffer
    private let detector: BallStrikeDetector

    /// Called (on the frames queue) when a complete pre+post window is ready.
    /// Ownership of the frame array is transferred to the caller.
    var onFrameWindowReady: (([CMSampleBuffer]) -> Void)?

    // MARK: - State machine

    private enum State {
        case idle
        /// Collecting post-strike frames.
        /// `preFrames`: snapshot from rolling buffer at detection moment.
        /// `remaining`: how many more post-strike frames to collect.
        case capturingPost(preFrames: [CMSampleBuffer], remaining: Int)
    }

    private var state: State = .idle

    // MARK: - Init

    init(buffer: RollingFrameBuffer = RollingFrameBuffer()) {
        self.rollingBuffer = buffer
        self.detector = BallStrikeDetector()
        super.init()

        detector.onStrike = { [weak self] event in
            self?.handleStrike(event)
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

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
                // Window complete — emit and reset
                let fullWindow = preFrames + [sampleBuffer]
                state = .idle
                onFrameWindowReady?(fullWindow)
            } else {
                state = .capturingPost(preFrames: preFrames + [sampleBuffer],
                                       remaining: newRemaining)
            }
        }
    }

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

    private func handleStrike(_ event: StrikeEvent) {
        guard case .idle = state else { return }  // ignore while already capturing
        let preFrames = rollingBuffer.snapshot()
        rollingBuffer.clear()
        state = .capturingPost(preFrames: preFrames, remaining: postStrikeFrameCount)
        print("🏌️ Strike detected — confidence \(String(format: "%.2f", event.confidence)), \(preFrames.count) pre-frames buffered")
    }
}
