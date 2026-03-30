import AVFoundation
import CoreML
import Vision

/// Strike detector using a YOLOv8-nano Core ML model to locate the golf ball
/// and detect its departure from the tee.
///
/// ## Adding the model
/// Export a YOLOv8-nano model trained on golf-ball images:
/// ```
/// pip install ultralytics coremltools
/// yolo export model=yolov8n.pt format=coreml nms=True imgsz=640
/// ```
/// Rename the output to `GolfBallDetector.mlpackage` and place it in
/// `SwingCap/Detection/Models/`. XcodeGen will bundle it automatically.
///
/// ## Detection strategy
/// 1. Run YOLO inference on every frame (Vision handles resize + color conversion).
/// 2. Track ball stability: ball must be seen in `minStableFrames` consecutive
///    frames before the tracker considers it "at rest on the tee".
/// 3. Departure: once tracking, if the ball is absent for `departureFrameThreshold`
///    consecutive frames, a `StrikeEvent` is emitted.
final class CoreMLBallDetector: StrikeDetectorProtocol {

    // MARK: - Tunable constants

    /// Minimum YOLO confidence to accept a ball observation.
    static let minBallConfidence: Float = 0.45
    /// Minimum normalised bounding-box area (width × height in [0,1] space).
    /// Filters out spurious detections of very small regions (~10×10 px at 720p).
    static let minBallNormalizedArea: CGFloat = 0.0001
    /// Consecutive frames the ball must appear before the tracker locks on.
    static let minStableFrames: Int = 3
    /// Consecutive frames without a detection (after lock-on) before declaring a strike.
    static let departureFrameThreshold: Int = 4
    /// Minimum seconds between consecutive strike events.
    static let detectionCooldownSeconds: TimeInterval = 3.0
    /// Label name used by the YOLO model for the golf ball class.
    static let targetClassName = "golf_ball"

    // MARK: - Vision

    private let request: VNCoreMLRequest
    private let visionQueue = DispatchQueue(
        label: "com.swingcap.detection.vision",
        qos: .userInteractive
    )

    // MARK: - Frame-drop guard

    private let processingLock = NSLock()
    private var isProcessing = false

    // MARK: - Tracking state

    private enum TrackingState {
        /// Waiting to see the ball for `minStableFrames` in a row.
        case searching(stableCount: Int)
        /// Ball locked-on; counting missed detections.
        case tracking(lastBox: CGRect, missedCount: Int)
    }

    private var trackingState: TrackingState = .searching(stableCount: 0)
    private var lastStrikeTime: CMTime = .invalid

    // MARK: - Callback

    var onStrike: ((StrikeEvent) -> Void)?

#if DEBUG
    private(set) var lastScore: Float = 0
#endif

    // MARK: - Init

    init(vnModel: VNCoreMLModel) {
        let req = VNCoreMLRequest(model: vnModel)
        // .scaleFill ensures the full 16:9 frame maps to the square model input
        // without letterboxing — a ball near the edges won't be cropped.
        req.imageCropAndScaleOption = .scaleFill
        self.request = req
    }

    // MARK: - StrikeDetectorProtocol

    func process(_ sampleBuffer: CMSampleBuffer) {
        // Drop frames if the Vision pipeline is still busy with the previous one.
        processingLock.lock()
        guard !isProcessing else { processingLock.unlock(); return }
        isProcessing = true
        processingLock.unlock()

        // Copy the buffer so it stays valid across the async queue hop.
        var bufferCopy: CMSampleBuffer?
        guard CMSampleBufferCreateCopy(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleBufferOut: &bufferCopy
        ) == noErr, let copy = bufferCopy else {
            processingLock.lock(); isProcessing = false; processingLock.unlock()
            return
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        visionQueue.async { [weak self] in
            defer {
                self?.processingLock.lock()
                self?.isProcessing = false
                self?.processingLock.unlock()
            }
            self?.runInference(on: copy, pts: pts)
        }
    }

    // MARK: - Inference (runs on visionQueue)

    private func runInference(on sampleBuffer: CMSampleBuffer, pts: CMTime) {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, options: [:])
        try? handler.perform([request])

        let topObs = bestBallObservation(from: request.results)
#if DEBUG
        lastScore = topObs?.labels.first?.confidence ?? 0
#endif
        updateTrackingState(observation: topObs, pts: pts)
    }

    private func bestBallObservation(
        from results: [VNObservation]?
    ) -> VNRecognizedObjectObservation? {
        results?
            .compactMap { $0 as? VNRecognizedObjectObservation }
            .filter { obs in
                guard let label = obs.labels.first else { return false }
                return label.identifier == Self.targetClassName
                    && label.confidence >= Self.minBallConfidence
                    && obs.boundingBox.width * obs.boundingBox.height >= Self.minBallNormalizedArea
            }
            .max { ($0.labels.first?.confidence ?? 0) < ($1.labels.first?.confidence ?? 0) }
    }

    // MARK: - State machine (runs on visionQueue)

    private func updateTrackingState(
        observation: VNRecognizedObjectObservation?,
        pts: CMTime
    ) {
        switch trackingState {
        case .searching(let stableCount):
            if let obs = observation {
                let newCount = stableCount + 1
                if newCount >= Self.minStableFrames {
                    trackingState = .tracking(lastBox: obs.boundingBox, missedCount: 0)
                } else {
                    trackingState = .searching(stableCount: newCount)
                }
            } else {
                // Reset stability counter on any miss while searching
                trackingState = .searching(stableCount: 0)
            }

        case .tracking(let lastBox, let missedCount):
            if let obs = observation {
                // Ball still visible — update position, reset miss counter
                trackingState = .tracking(lastBox: obs.boundingBox, missedCount: 0)
            } else {
                let newMissed = missedCount + 1
                if newMissed >= Self.departureFrameThreshold {
                    // Ball has departed — enforce cooldown then emit
                    if shouldEmitStrike(at: pts) {
                        lastStrikeTime = pts
                        let event = StrikeEvent(timestamp: pts, confidence: 0.9)
                        onStrike?(event)
                        print("🏌️ CoreML: ball departed from \(lastBox) — strike emitted")
                    }
                    trackingState = .searching(stableCount: 0)
                } else {
                    trackingState = .tracking(lastBox: lastBox, missedCount: newMissed)
                }
            }
        }
    }

    private func shouldEmitStrike(at pts: CMTime) -> Bool {
        guard lastStrikeTime.isValid else { return true }
        return CMTimeGetSeconds(CMTimeSubtract(pts, lastStrikeTime)) >= Self.detectionCooldownSeconds
    }
}
