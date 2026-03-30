import AVFoundation

/// Receives raw `CMSampleBuffer` frames from `AVCaptureVideoDataOutput`
/// and fans them out to the rolling buffer and (later) the strike detector.
///
/// One instance is shared across the capture pipeline for its lifetime.
final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Dependencies

    let rollingBuffer: RollingFrameBuffer

    // Plugged in during Phase 2 when the detection pipeline is ready.
    // var strikeDetector: BallStrikeDetector?

    // MARK: - Init

    init(buffer: RollingFrameBuffer = RollingFrameBuffer()) {
        self.rollingBuffer = buffer
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        rollingBuffer.append(sampleBuffer)
        // Phase 2: forward to strikeDetector
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
}
