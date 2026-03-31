import CoreMedia
import CoreVideo

/// Strike detector based on inter-frame luma motion energy.
/// Used as the immediate fallback when `GolfBallDetector.mlpackage` is absent.
///
/// ## Algorithm
/// 1. Lock the Y-plane of the current and previous `CVPixelBuffer`.
/// 2. Sample every `samplingStep`-th pixel (row and column) for performance.
/// 3. Compute the mean absolute difference across all sampled pixels,
///    normalised to [0, 1] by dividing by 255.
/// 4. Compare against `effectiveThreshold`. A quiet scene (camera shake, wind)
///    typically scores < 0.01; a full golf swing exceeds 0.04.
///
/// ## Cooldown
/// After a strike is emitted the detector ignores subsequent frames for
/// `effectiveCooldown` seconds to avoid a single swing producing multiple clips.
///
/// ## Tuning
/// `motionThreshold` and `cooldownSeconds` are static defaults. The user can
/// override them in Settings — those values are stored in `UserDefaults` and
/// read at runtime by `effectiveThreshold` / `effectiveCooldown` so changes
/// take effect immediately without restarting detection.
final class MotionThresholdDetector: StrikeDetectorProtocol {

    // MARK: - Tunable constants (fallback defaults)

    /// Mean absolute luma difference (fraction of 255) to classify as a strike.
    /// Quiet-scene noise is typically < 0.01; a full swing exceeds 0.04.
    static let motionThreshold: Float = 0.035

    /// Minimum seconds between consecutive strike events.
    static let cooldownSeconds: TimeInterval = 3.0

    /// Sample every Nth pixel row and column for performance.
    /// 8 gives ~1/64 of all pixels with negligible accuracy cost.
    private static let samplingStep = 8

    // MARK: - Runtime-tunable values (read from UserDefaults set by SettingsView)

    /// Returns the motion threshold the user has set in Settings, or the
    /// static default if no custom value has been written to UserDefaults yet.
    private var effectiveThreshold: Float {
        let v = UserDefaults.standard.double(forKey: "motionThreshold")
        return v > 0 ? Float(v) : Self.motionThreshold
    }

    /// Returns the cooldown duration from Settings, or the static default.
    private var effectiveCooldown: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "cooldownSeconds")
        return v > 0 ? v : Self.cooldownSeconds
    }

    // MARK: - State

    /// Previous frame's pixel buffer, retained for the next diff calculation.
    private var previousPixelBuffer: CVPixelBuffer?
    /// Timestamp of the most recent emitted strike; used to enforce cooldown.
    private var lastStrikeTime: CMTime = .invalid

    var onStrike: ((StrikeEvent) -> Void)?

#if DEBUG
    private(set) var lastScore: Float = 0
#endif

    // MARK: - StrikeDetectorProtocol

    /// Processes one camera frame.
    ///
    /// Called on the camera frames queue. The diff is computed synchronously
    /// (the subsampling keeps it under ~0.5ms on an A14), so there is no async
    /// dispatch here — we return before the next frame arrives.
    func process(_ sampleBuffer: CMSampleBuffer) {
        guard let current = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Always update previousPixelBuffer at the end, even if we skip this frame.
        defer { previousPixelBuffer = current }
        guard let previous = previousPixelBuffer else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Enforce cooldown: skip scoring if we recently emitted a strike.
        if lastStrikeTime.isValid {
            let elapsed = CMTimeGetSeconds(CMTimeSubtract(pts, lastStrikeTime))
            guard elapsed >= effectiveCooldown else { return }
        }

        let score = motionScore(current: current, previous: previous)
#if DEBUG
        lastScore = score
#endif
        let threshold = effectiveThreshold
        guard score > threshold else { return }

        lastStrikeTime = pts
        // Confidence is a simple linear scale: at exactly `threshold` it's ~0.5,
        // at 2× threshold it's capped at 1.0.
        let event = StrikeEvent(
            timestamp: pts,
            confidence: min(1.0, score / threshold * 0.5)
        )
        onStrike?(event)
    }

    // MARK: - Luma differencing

    /// Computes the mean absolute per-pixel luma (Y-plane) difference between
    /// two consecutive frames, normalised to [0, 1].
    ///
    /// We lock both buffers for read-only access, read raw byte pointers from
    /// the Y-plane (plane index 0 of the YCbCr bi-planar format), then step
    /// through them at `samplingStep` intervals to avoid a full-resolution scan.
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
        // `stride` is bytes-per-row which may be padded beyond `width`; we use
        // it as the row increment to avoid reading padding bytes as pixel data.
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
