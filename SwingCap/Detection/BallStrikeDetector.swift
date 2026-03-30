import AVFoundation
import CoreML
import Vision

/// Routes strike detection to the best available implementation at runtime.
///
/// On init the app immediately starts using `MotionThresholdDetector` so
/// detection works from the very first frame. A background task then loads
/// `GolfBallDetector.mlpackage` — if found, the implementation is swapped
/// to `CoreMLBallDetector` with no interruption to the camera pipeline.
///
/// `FrameProcessor` sees only this type and calls `process(_:)` / `onStrike`
/// — it never needs to know which strategy is active.
final class BallStrikeDetector {

    // MARK: - Model bundle name

    private static let mlPackageName = "GolfBallDetector"

    // MARK: - Implementation (lock-protected for async swap)

    private var _implementation: any StrikeDetectorProtocol
    private let implLock = NSLock()

    private var implementation: any StrikeDetectorProtocol {
        get { implLock.withLock { _implementation } }
        set { implLock.withLock { _implementation = newValue } }
    }

    // MARK: - StrikeDetectorProtocol forwarding

    var onStrike: ((StrikeEvent) -> Void)? {
        get { implLock.withLock { _implementation.onStrike } }
        set { implLock.withLock { _implementation.onStrike = newValue } }
    }

    func process(_ sampleBuffer: CMSampleBuffer) {
        implementation.process(sampleBuffer)
    }

    // MARK: - Init

    init() {
        // Start immediately with motion threshold — zero wait.
        _implementation = MotionThresholdDetector()

        // Upgrade to Core ML in the background (~100–500ms for model load).
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if let vnModel = Self.loadMLModel() {
                let coreML = CoreMLBallDetector(vnModel: vnModel)
                // Transfer the callback before swapping so no event is missed.
                coreML.onStrike = self.onStrike
                self.implementation = coreML
                print("SwingCap: upgraded to Core ML ball detector")
            } else {
                print("⚠️ SwingCap: \(Self.mlPackageName).mlpackage not found — using motion threshold detector")
            }
        }
    }

    // MARK: - Model loading

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
