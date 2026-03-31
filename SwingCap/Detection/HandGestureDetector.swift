import AVFoundation
import Vision

/// Detects thumbs-up and thumbs-down hand gestures using Apple's
/// `VNDetectHumanHandPoseRequest`.
///
/// ## How it works
///
/// Vision returns normalised 2-D coordinates for 21 hand landmark joints.
/// The classifier analyses the relative positions of those joints each frame:
///
/// **Thumbs-up**: thumb tip is above the thumb MCP joint (base knuckle) AND
/// at least 3 of the 4 non-thumb fingertips are below their own PIP joints
/// (fingers are curled into a fist).
///
/// **Thumbs-down**: same curl condition, but the thumb tip is below the MCP.
///
/// **Hold-for-N-frames**: the same gesture must be detected for
/// `requiredStableFrames` consecutive frames before a `GestureEvent` is
/// emitted. This prevents mid-swing arm positions from producing false
/// positives.
///
/// ## Coordinate system
///
/// `VNDetectHumanHandPoseRequest` uses Vision's normalised image coordinates:
/// (0,0) = bottom-left, (1,1) = top-right. So a thumb pointing **up** has a
/// tip with a **higher** Y value than its base, and vice versa.
///
/// ## Threading
///
/// `process(_:)` is called on the camera frames queue. Inference is dispatched
/// to `visionQueue` asynchronously; frames are dropped while the previous
/// inference is in flight via the `isProcessing` guard — identical to the
/// pattern in `CoreMLBallDetector`.
///
/// ## Tuning
///
/// `minJointConfidence`, `requiredStableFrames`, and `thumbAngleThreshold`
/// are constants tunable to device distance and lighting conditions.
final class HandGestureDetector {

    // MARK: - Tunable constants

    /// Minimum Vision landmark confidence to trust a joint position.
    /// Joints below this threshold are treated as undetected.
    static let minJointConfidence: Float = 0.5

    /// How many consecutive frames must agree on the same gesture before
    /// the detector fires its callback. At 60fps, 15 frames ≈ 0.25 s.
    static let requiredStableFrames = 15

    /// Minimum normalised Y-axis offset between thumb tip and thumb MCP for
    /// a thumbs-up/down classification. Filters out nearly-horizontal thumbs.
    static let thumbAxisThreshold: Float = 0.04

    /// Minimum fraction of non-thumb fingers that must appear curled (tip
    /// below PIP in normalised coords) for the gesture to be accepted.
    /// 0.6 = at least 3 of the 4 non-thumb fingers.
    static let minCurledFingerFraction: Float = 0.6

    // MARK: - Callback

    /// Fired (on the camera frames queue via a DispatchQueue hop) when a
    /// stable gesture is confirmed. Set this before the detector is active.
    var onGesture: ((ShotRating, Float) -> Void)?

    // MARK: - Vision

    private let request = VNDetectHumanHandPoseRequest()
    private let visionQueue = DispatchQueue(
        label: "com.swingcap.gesture.vision",
        qos: .userInteractive
    )

    // MARK: - Frame-drop guard

    private let processingLock = NSLock()
    private var isProcessing = false

    // MARK: - Stability state

    /// The gesture agreed on across the current run of stable frames.
    private var currentGesture: ShotRating?
    /// How many consecutive frames have agreed on `currentGesture`.
    private var stableCount = 0

    // MARK: - Init

    init() {
        // Limit to one hand — we only need the rating hand.
        request.maximumHandCount = 1
    }

    // MARK: - Public API

    /// Resets stability state. Call this when the gesture window opens so
    /// any leftover state from a previous window doesn't immediately fire.
    func reset() {
        processingLock.lock()
        currentGesture = nil
        stableCount = 0
        processingLock.unlock()
    }

    /// Processes one camera frame. Returns immediately if inference is already
    /// in flight for the previous frame.
    func process(_ sampleBuffer: CMSampleBuffer) {
        processingLock.lock()
        guard !isProcessing else { processingLock.unlock(); return }
        isProcessing = true
        processingLock.unlock()

        // Copy buffer so it remains valid across the async queue hop.
        var bufferCopy: CMSampleBuffer?
        guard CMSampleBufferCreateCopy(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleBufferOut: &bufferCopy
        ) == noErr, let copy = bufferCopy else {
            processingLock.lock(); isProcessing = false; processingLock.unlock()
            return
        }

        visionQueue.async { [weak self] in
            defer {
                self?.processingLock.lock()
                self?.isProcessing = false
                self?.processingLock.unlock()
            }
            self?.runInference(on: copy)
        }
    }

    // MARK: - Inference (runs on visionQueue)

    private func runInference(on sampleBuffer: CMSampleBuffer) {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, options: [:])
        try? handler.perform([request])

        guard let observation = request.results?.first as? VNHumanHandPoseObservation else {
            // No hand detected — reset the stability counter.
            updateStability(with: nil)
            return
        }

        let detected = classify(observation)
        updateStability(with: detected)
    }

    // MARK: - Classifier

    /// Returns `.good` (thumbs-up), `.bad` (thumbs-down), or `nil` if the
    /// hand pose doesn't meet the gesture criteria.
    ///
    /// All joints use Vision's **normalised image coordinates**:
    /// Y = 0 at the **bottom** of the image, Y = 1 at the **top**.
    /// So "thumb tip higher than base" means `tipY > mcpY`.
    private func classify(_ obs: VNHumanHandPoseObservation) -> ShotRating? {
        guard
            let thumbTip  = joint(obs, .thumbTip),
            let thumbMCP  = joint(obs, .thumbCMC),   // base of thumb (carpometacarpal)
            fingersAreCurled(obs)
        else { return nil }

        let verticalOffset = thumbTip.y - thumbMCP.y  // positive = tip above base

        if verticalOffset > Self.thumbAxisThreshold {
            return .good   // thumbs-up
        } else if verticalOffset < -Self.thumbAxisThreshold {
            return .bad    // thumbs-down
        }
        return nil   // horizontal — ambiguous
    }

    /// Returns the normalised point for `jointName` if its confidence meets
    /// the minimum threshold, otherwise `nil`.
    private func joint(
        _ obs: VNHumanHandPoseObservation,
        _ jointName: VNHumanHandPoseObservation.JointName
    ) -> CGPoint? {
        guard
            let point = try? obs.recognizedPoint(jointName),
            point.confidence >= Self.minJointConfidence
        else { return nil }
        return point.location   // normalised (0,0)=bottom-left, (1,1)=top-right
    }

    /// Returns `true` if at least `minCurledFingerFraction` of the four
    /// non-thumb fingers appear curled (fingertip Y < PIP Y, meaning the
    /// tip is lower in the image than the middle knuckle).
    private func fingersAreCurled(_ obs: VNHumanHandPoseObservation) -> Bool {
        let fingerPairs: [(VNHumanHandPoseObservation.JointName,
                           VNHumanHandPoseObservation.JointName)] = [
            (.indexTip, .indexPIP),
            (.middleTip, .middlePIP),
            (.ringTip, .ringPIP),
            (.littleTip, .littlePIP)
        ]

        var curledCount = 0
        var visibleCount = 0

        for (tipName, pipName) in fingerPairs {
            guard
                let tip = joint(obs, tipName),
                let pip = joint(obs, pipName)
            else { continue }
            visibleCount += 1
            // In normalised image coords (Y=0 bottom), a curled finger has
            // its tip *lower* in the frame than its PIP knuckle → tip.y < pip.y
            if tip.y < pip.y { curledCount += 1 }
        }

        guard visibleCount > 0 else { return false }
        return Float(curledCount) / Float(visibleCount) >= Self.minCurledFingerFraction
    }

    // MARK: - Stability tracking (runs on visionQueue)

    /// Advances or resets the stable-frame counter.
    /// When `requiredStableFrames` consecutive frames agree, fires `onGesture`.
    private func updateStability(with gesture: ShotRating?) {
        if gesture == currentGesture, let g = gesture {
            stableCount += 1
            if stableCount == Self.requiredStableFrames {
                let confidence = Float(stableCount) / Float(Self.requiredStableFrames + 5)
                let callback = onGesture
                DispatchQueue.main.async { callback?(g, min(1.0, confidence)) }
            }
        } else {
            currentGesture = gesture
            stableCount = gesture != nil ? 1 : 0
        }
    }
}
