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
/// 1. **Inference**: Run YOLO on every frame via `VNCoreMLRequest` (Vision
///    handles the resize + colour conversion from YCbCr → RGB internally).
/// 2. **Stability**: The ball must appear in `minStableFrames` consecutive
///    frames before the tracker locks on. This prevents a stray detection from
///    immediately starting a tracking window.
/// 3. **Departure**: Once locked on, if the ball is absent for
///    `departureFrameThreshold` consecutive frames, a `StrikeEvent` is emitted.
///    Requiring multiple missed frames filters out momentary YOLO misses.
/// 4. **Frame dropping**: Vision inference takes ~5–10ms; if the previous
///    frame is still being processed when a new one arrives, the new one is
///    dropped (`isProcessing` guard). This prevents a queue pile-up.
///
/// ## Runtime tuning
/// `minBallConfidence` and `departureFrameThreshold` are static defaults.
/// `effectiveMinConfidence` and `effectiveDepartureThreshold` read user
/// overrides from `UserDefaults` (set by `SettingsView`) at call time.
final class CoreMLBallDetector: StrikeDetectorProtocol {

    // MARK: - Tunable constants (fallback defaults)

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

    // MARK: - Runtime-tunable values (read from UserDefaults set by SettingsView)

    /// Returns the confidence cutoff the user has set in Settings, or the static default.
    private var effectiveMinConfidence: Float {
        let v = UserDefaults.standard.double(forKey: "mlMinConfidence")
        return v > 0 ? Float(v) : Self.minBallConfidence
    }

    /// Returns the departure threshold from Settings, or the static default.
    /// Stored as `Double` in UserDefaults because `@AppStorage` only supports
    /// `Double`/`Int`/`String`; we truncate to `Int` at read time.
    private var effectiveDepartureThreshold: Int {
        let v = UserDefaults.standard.double(forKey: "departureFrameThreshold")
        return v > 0 ? Int(v) : Self.departureFrameThreshold
    }

    // MARK: - Vision

    /// Single `VNCoreMLRequest` created once at init — reusing it avoids
    /// repeated model compilation overhead on each frame.
    private let request: VNCoreMLRequest
    /// Serial queue for Vision inference. Using `.userInteractive` QoS ensures
    /// we compete fairly with the camera frames queue.
    private let visionQueue = DispatchQueue(
        label: "com.swingcap.detection.vision",
        qos: .userInteractive
    )

    // MARK: - Frame-drop guard

    /// Protects `isProcessing` which is written from two queues:
    /// the camera frames queue (sets `true`) and `visionQueue` (sets `false`).
    private let processingLock = NSLock()
    /// `true` while an inference is in flight. New frames are dropped when set.
    private var isProcessing = false

    // MARK: - Tracking state

    /// Two-state machine tracking the ball's lifecycle in the scene.
    private enum TrackingState {
        /// Waiting to see the ball for `minStableFrames` in a row.
        /// `stableCount` increments each frame the ball is detected;
        /// any miss resets it to 0.
        case searching(stableCount: Int)
        /// Ball locked-on; counting missed detections toward departure.
        /// `lastBox` is the most recent bounding box, used for future
        /// position comparison if needed. `missedCount` increments each
        /// frame the ball is not detected.
        case tracking(lastBox: CGRect, missedCount: Int)
    }

    private var trackingState: TrackingState = .searching(stableCount: 0)
    /// Timestamp of the most recent emitted strike; used to enforce cooldown.
    private var lastStrikeTime: CMTime = .invalid

    // MARK: - Callback

    var onStrike: ((StrikeEvent) -> Void)?

#if DEBUG
    private(set) var lastScore: Float = 0
#endif

    // MARK: - Init

    init(vnModel: VNCoreMLModel) {
        let req = VNCoreMLRequest(model: vnModel)
        // `.scaleFill` maps the full 16:9 frame to the square model input
        // without letterboxing — a ball near the edges won't be cropped.
        req.imageCropAndScaleOption = .scaleFill
        self.request = req
    }

    // MARK: - StrikeDetectorProtocol

    /// Processes one camera frame.
    ///
    /// Called on the camera frames queue. If Vision is still busy with the
    /// previous frame, the new frame is dropped — this is intentional and
    /// preferable to letting a queue of pending frames grow unbounded.
    ///
    /// We copy the buffer before the async dispatch because `AVFoundation`
    /// may reuse the buffer's backing storage after this method returns.
    func process(_ sampleBuffer: CMSampleBuffer) {
        // Drop frame if Vision is still busy.
        processingLock.lock()
        guard !isProcessing else { processingLock.unlock(); return }
        isProcessing = true
        processingLock.unlock()

        // Copy the buffer so it remains valid across the visionQueue hop.
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
                // Always clear the flag so the next frame isn't blocked forever.
                self?.processingLock.lock()
                self?.isProcessing = false
                self?.processingLock.unlock()
            }
            self?.runInference(on: copy, pts: pts)
        }
    }

    // MARK: - Inference (runs on visionQueue)

    /// Runs the YOLO model, extracts the best ball observation, then updates
    /// the tracking state machine.
    private func runInference(on sampleBuffer: CMSampleBuffer, pts: CMTime) {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, options: [:])
        try? handler.perform([request])

        let topObs = bestBallObservation(from: request.results)
#if DEBUG
        lastScore = topObs?.labels.first?.confidence ?? 0
#endif
        updateTrackingState(observation: topObs, pts: pts)
    }

    /// Filters YOLO results down to the single highest-confidence `golf_ball`
    /// detection that meets the area and confidence thresholds.
    private func bestBallObservation(
        from results: [VNObservation]?
    ) -> VNRecognizedObjectObservation? {
        results?
            .compactMap { $0 as? VNRecognizedObjectObservation }
            .filter { obs in
                guard let label = obs.labels.first else { return false }
                return label.identifier == Self.targetClassName
                    && label.confidence >= effectiveMinConfidence
                    && obs.boundingBox.width * obs.boundingBox.height >= Self.minBallNormalizedArea
            }
            .max { ($0.labels.first?.confidence ?? 0) < ($1.labels.first?.confidence ?? 0) }
    }

    // MARK: - State machine (runs on visionQueue)

    /// Advances the tracking state based on whether a ball observation was found.
    ///
    /// `.searching` → `.tracking`: ball seen for `minStableFrames` in a row.
    /// `.tracking` → emit + `.searching`: ball absent for `effectiveDepartureThreshold` frames.
    private func updateTrackingState(
        observation: VNRecognizedObjectObservation?,
        pts: CMTime
    ) {
        switch trackingState {
        case .searching(let stableCount):
            if let obs = observation {
                let newCount = stableCount + 1
                if newCount >= Self.minStableFrames {
                    // Ball is stable enough to lock on.
                    trackingState = .tracking(lastBox: obs.boundingBox, missedCount: 0)
                } else {
                    trackingState = .searching(stableCount: newCount)
                }
            } else {
                // Any miss while searching resets the stability counter.
                trackingState = .searching(stableCount: 0)
            }

        case .tracking(let lastBox, let missedCount):
            if let obs = observation {
                // Ball still visible — update position, reset miss counter.
                trackingState = .tracking(lastBox: obs.boundingBox, missedCount: 0)
            } else {
                let newMissed = missedCount + 1
                if newMissed >= effectiveDepartureThreshold {
                    // Ball has departed — enforce cooldown then emit.
                    if shouldEmitStrike(at: pts) {
                        lastStrikeTime = pts
                        let event = StrikeEvent(timestamp: pts, confidence: 0.9)
                        onStrike?(event)
                        print("🏌️ CoreML: ball departed from \(lastBox) — strike emitted")
                    }
                    // Return to searching so we can detect the next shot.
                    trackingState = .searching(stableCount: 0)
                } else {
                    trackingState = .tracking(lastBox: lastBox, missedCount: newMissed)
                }
            }
        }
    }

    /// Returns `true` if enough time has passed since the last emitted strike.
    private func shouldEmitStrike(at pts: CMTime) -> Bool {
        guard lastStrikeTime.isValid else { return true }
        return CMTimeGetSeconds(CMTimeSubtract(pts, lastStrikeTime)) >= Self.detectionCooldownSeconds
    }
}
