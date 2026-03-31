import AVFoundation
import CoreML
import Vision

/// Routes strike detection to the best available implementation at runtime.
///
/// ## Strategy pattern + warm-start upgrade
///
/// The app must start detecting immediately when the session opens — there
/// is no time to wait for a Core ML model to load (~100–500ms). So:
///
/// 1. `init()` synchronously creates a `MotionThresholdDetector` so detection
///    works from the very first camera frame.
/// 2. A background `Task.detached` loads `GolfBallDetector.mlpackage`
///    (Neural Engine compilation happens here). If it succeeds, the
///    implementation is swapped to `CoreMLBallDetector` with no interruption
///    to the camera pipeline.
///
/// `FrameProcessor` calls `process(_:)` and reads `onStrike` on this type
/// only — it never sees the underlying strategy, so the swap is transparent.
///
/// ## Thread safety
///
/// `_implementation` is protected by `implLock` because it can be read from
/// the camera frames queue and written from the background upgrade task at the
/// same time. We hold the lock only for the duration of the read/write, not
/// during inference, to keep contention negligible.
final class BallStrikeDetector {

    // MARK: - Model bundle name

    private static let mlPackageName = "GolfBallDetector"

    // MARK: - Implementation (lock-protected for async swap)

    private var _implementation: any StrikeDetectorProtocol
    private let implLock = NSLock()

    /// Thread-safe accessor for the current implementation.
    private var implementation: any StrikeDetectorProtocol {
        get { implLock.withLock { _implementation } }
        set { implLock.withLock { _implementation = newValue } }
    }

    // MARK: - StrikeDetectorProtocol forwarding

    /// Forwarding getter/setter that go through the lock so callers never
    /// need to know about the underlying strategy.
    var onStrike: ((StrikeEvent) -> Void)? {
        get { implLock.withLock { _implementation.onStrike } }
        set { implLock.withLock { _implementation.onStrike = newValue } }
    }

    /// Dispatches the frame to whatever strategy is currently active.
    func process(_ sampleBuffer: CMSampleBuffer) {
        implementation.process(sampleBuffer)
    }

    // MARK: - Init

    init() {
        // Start immediately with motion threshold — zero latency.
        _implementation = MotionThresholdDetector()

        // Upgrade to Core ML in the background (~100–500ms for model compilation).
        // `.userInitiated` priority competes well with the camera queue without
        // blocking the main thread.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if let vnModel = Self.loadMLModel() {
                let coreML = CoreMLBallDetector(vnModel: vnModel)
                // Transfer the onStrike callback before swapping so no event
                // is missed during the brief implementation swap.
                coreML.onStrike = self.onStrike
                self.implementation = coreML
                print("SwingCap: upgraded to Core ML ball detector")
            } else {
                print("⚠️ SwingCap: \(Self.mlPackageName).mlpackage not found — using motion threshold detector")
            }
        }
    }

    // MARK: - Model loading

    /// Attempts to load `GolfBallDetector.mlpackage` from the app bundle and
    /// wrap it in a `VNCoreMLModel` for use with `VNCoreMLRequest`.
    ///
    /// Returns `nil` (silently) if the model file is absent — callers fall
    /// back to `MotionThresholdDetector` in this case.
    private static func loadMLModel() -> VNCoreMLModel? {
        guard
            let url = Bundle.main.url(
                forResource: mlPackageName,
                withExtension: "mlpackage"
            ),
            let mlModel = try? MLModel(contentsOf: url),
            let vnModel = try? VNCoreMLModel(for: mlModel)
        else { return nil }
        return vnModel
    }

    // MARK: - Debug

#if DEBUG
    /// Exposes the active detector type name for unit tests and the debug overlay.
    var detectorTypeName: String { String(describing: type(of: implementation)) }
    /// Most-recent raw detection score forwarded from the active implementation.
    var lastScore: Float { implementation.lastScore }
#endif
}
