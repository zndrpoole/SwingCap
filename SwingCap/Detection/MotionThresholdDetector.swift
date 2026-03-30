import CoreMedia
import CoreVideo

/// Strike detector based on inter-frame luma motion energy.
/// Used as the immediate fallback when `GolfBallDetector.mlpackage` is absent.
///
/// Works by computing the mean absolute difference of Y-plane values
/// between consecutive frames. A golf swing produces a large motion score
/// as the club and departing ball sweep through the frame.
final class MotionThresholdDetector: StrikeDetectorProtocol {

    // MARK: - Tunable constants

    /// Mean absolute luma difference (fraction of 255) to classify as a strike.
    /// Quiet-scene noise is typically < 0.01; a full swing exceeds 0.04.
    static let motionThreshold: Float = 0.035

    /// Minimum seconds between consecutive strike events.
    static let cooldownSeconds: TimeInterval = 3.0

    /// Sample every Nth pixel row and column for performance.
    /// 8 gives ~1/64 of all pixels with negligible accuracy cost.
    private static let samplingStep = 8

    // MARK: - State

    private var previousPixelBuffer: CVPixelBuffer?
    private var lastStrikeTime: CMTime = .invalid

    var onStrike: ((StrikeEvent) -> Void)?

    // MARK: - StrikeDetectorProtocol

    func process(_ sampleBuffer: CMSampleBuffer) {
        guard let current = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        defer { previousPixelBuffer = current }
        guard let previous = previousPixelBuffer else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if lastStrikeTime.isValid {
            let elapsed = CMTimeGetSeconds(CMTimeSubtract(pts, lastStrikeTime))
            guard elapsed >= Self.cooldownSeconds else { return }
        }

        let score = motionScore(current: current, previous: previous)
        guard score > Self.motionThreshold else { return }

        lastStrikeTime = pts
        let event = StrikeEvent(
            timestamp: pts,
            confidence: min(1.0, score / Self.motionThreshold * 0.5)
        )
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
