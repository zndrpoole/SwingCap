import CoreMedia
import CoreVideo

/// Placeholder strike detector based on inter-frame motion energy.
///
/// Works by computing the mean absolute difference of luma (Y-plane) values
/// between consecutive frames. A swing produces a sudden large motion score
/// as the club and departing ball sweep through the frame.
///
/// Replace the body of `process(_:)` with Core ML inference in Phase 3.
final class BallStrikeDetector {

    // MARK: - Tunable constants

    /// Mean absolute luma difference, as a fraction of 255, required to
    /// classify a frame pair as a strike. Typical quiet-scene noise is
    /// < 0.01; a full swing through frame easily exceeds 0.04.
    static let motionThreshold: Float = 0.035

    /// Minimum seconds between consecutive strike events (prevents the tail
    /// of a swing from triggering a second clip).
    static let cooldownSeconds: TimeInterval = 3.0

    /// Sample every Nth pixel row and column when computing motion.
    /// Higher = faster but coarser. 8 gives ~1/64 of pixels at negligible
    /// accuracy cost for this use-case.
    private static let samplingStep = 8

    // MARK: - State

    private var previousPixelBuffer: CVPixelBuffer?
    private var lastStrikeTime: CMTime = .invalid

    /// Called on the camera frames queue when a strike is detected.
    var onStrike: ((StrikeEvent) -> Void)?

    // MARK: - API

    func process(_ sampleBuffer: CMSampleBuffer) {
        guard let current = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        defer { previousPixelBuffer = current }
        guard let previous = previousPixelBuffer else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Enforce cooldown
        if lastStrikeTime.isValid {
            let elapsed = CMTimeGetSeconds(CMTimeSubtract(pts, lastStrikeTime))
            guard elapsed >= Self.cooldownSeconds else { return }
        }

        let score = motionScore(current: current, previous: previous)
        guard score > Self.motionThreshold else { return }

        lastStrikeTime = pts
        let event = StrikeEvent(timestamp: pts, confidence: min(1.0, score / Self.motionThreshold * 0.5))
        onStrike?(event)
    }

    // MARK: - Luma differencing

    private func motionScore(current: CVPixelBuffer, previous: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(current, .readOnly)
        CVPixelBufferLockBaseAddress(previous, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(current, .readOnly)
            CVPixelBufferUnlockBaseAddress(previous, .readOnly)
        }

        // Y-plane is plane 0 in kCVPixelFormatType_420YpCbCr8BiPlanar*
        guard
            let curBase  = CVPixelBufferGetBaseAddressOfPlane(current,  0),
            let prevBase = CVPixelBufferGetBaseAddressOfPlane(previous, 0)
        else { return 0 }

        let width  = CVPixelBufferGetWidthOfPlane(current, 0)
        let height = CVPixelBufferGetHeightOfPlane(current, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(current, 0)
        let step   = Self.samplingStep

        let cur  = curBase.assumingMemoryBound(to: UInt8.self)
        let prev = prevBase.assumingMemoryBound(to: UInt8.self)

        var totalDiff: Int64 = 0
        var sampleCount: Int64 = 0

        var row = 0
        while row < height {
            var col = 0
            while col < width {
                let idx = row * stride + col
                totalDiff += Int64(abs(Int32(cur[idx]) - Int32(prev[idx])))
                sampleCount += 1
                col += step
            }
            row += step
        }

        guard sampleCount > 0 else { return 0 }
        return Float(totalDiff) / Float(sampleCount) / 255.0
    }
}
