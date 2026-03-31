import AVFoundation
import Observation
import UIKit

/// Configures and manages the `AVCaptureSession` lifecycle.
///
/// **Setup**: `configure()` must be called before `start()`. It runs
/// synchronously on `sessionQueue` to satisfy AVFoundation's thread
/// requirement (session configuration must happen off the main thread).
///
/// **60 fps**: The app needs 60fps so the rolling buffer has ~120 frames
/// for a 2-second pre-strike window. `findFormat` picks the first device
/// format that supports at least 1280px width at ≥ 60fps.
///
/// **Preview**: `AVCaptureVideoPreviewLayer` is created here and stored in
/// `previewLayer`; `CameraPreviewView` attaches it to a `UIView` sublayer.
///
/// **Frame delivery**: The `frameProcessor` property accepts an
/// `AVCaptureVideoDataOutputSampleBufferDelegate` — swapping it at runtime
/// calls `rebindDelegate()` with no interruption to the capture session.
///
/// **Background/interruption**: After `configure()` is called the session
/// observes `UIApplication` active/inactive notifications and
/// `AVCaptureSession` interruption notifications so it automatically
/// stops when the app backgrounds and restarts when it returns.
@Observable
final class CameraSession: NSObject {

    // MARK: - Public state

    var isRunning = false
    var error: CameraError?
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Private

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()

    /// All session mutations run on this serial queue (AVFoundation requirement).
    private let sessionQueue = DispatchQueue(label: "com.swingcap.camera.session",
                                             qos: .userInteractive)

    /// Setting this live-swaps the frame delegate without stopping the session.
    var frameProcessor: FrameProcessor? {
        didSet { rebindDelegate() }
    }

    // MARK: - Setup

    /// Configures the capture session: input device → 60fps format → output → preview layer.
    /// Blocks the caller until configuration is complete (runs sync on sessionQueue).
    /// - Throws: `CameraError` if any step fails.
    func configure() throws {
        // Must not be called on sessionQueue — it's sync-dispatched below.
        try sessionQueue.sync { try self._configure() }
    }

    private func _configure() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .hd1280x720

        // Input — back wide-angle camera is the standard choice for a tripod shot.
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                  for: .video,
                                                  position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else { throw CameraError.deviceUnavailable }
        captureSession.addInput(input)

        // Lock in 60fps format. `device.activeFormat` controls the format but
        // min/max frame duration pins the actual frame rate; without both the
        // camera may drift to 30fps under low light.
        let targetFormat = try findFormat(for: device, minWidth: 1280, minFPS: 60)
        try device.lockForConfiguration()
        device.activeFormat = targetFormat
        let frameDuration = CMTime(value: 1, timescale: 60)
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
        device.unlockForConfiguration()

        // Output — YCbCr bi-planar gives us direct Y-plane access for the
        // motion detector without a colour conversion step.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        // Keep false so the rolling buffer never starves on a fast swing;
        // frames dropped by AVFoundation can't be recovered after the fact.
        videoOutput.alwaysDiscardsLateVideoFrames = false

        guard captureSession.canAddOutput(videoOutput) else {
            throw CameraError.outputUnavailable
        }
        captureSession.addOutput(videoOutput)

        // Preview layer — must be created before startRunning so the viewfinder
        // is ready when the session starts. Posted to main thread because
        // `previewLayer` drives a SwiftUI observable update.
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async { self.previewLayer = layer }

        rebindDelegate()
        subscribeToNotifications()
    }

    // MARK: - Notifications

    /// Subscribes to system events that should pause or resume the session.
    /// Called once at the end of `_configure()`.
    private func subscribeToNotifications() {
        let nc = NotificationCenter.default

        // Stop recording when the user switches apps or locks the screen so
        // AVFoundation doesn't consume resources in the background.
        nc.addObserver(self,
                       selector: #selector(appWillResignActive),
                       name: UIApplication.willResignActiveNotification,
                       object: nil)

        // Restart as soon as the user returns — the session is already
        // configured so `start()` just calls `startRunning()`.
        nc.addObserver(self,
                       selector: #selector(appDidBecomeActive),
                       name: UIApplication.didBecomeActiveNotification,
                       object: nil)

        // System-level interruptions (phone call, Siri, FaceTime) can pause
        // the session mid-capture; update the public `isRunning` flag so the
        // UI can reflect the paused state correctly.
        nc.addObserver(self,
                       selector: #selector(sessionWasInterrupted),
                       name: .AVCaptureSessionWasInterrupted,
                       object: captureSession)

        // Automatically resume once the interruption (call, Siri etc.) ends.
        nc.addObserver(self,
                       selector: #selector(sessionInterruptionEnded),
                       name: .AVCaptureSessionInterruptionEnded,
                       object: captureSession)
    }

    @objc private func appWillResignActive() { stop() }

    @objc private func appDidBecomeActive() { start() }

    @objc private func sessionWasInterrupted() {
        // AVCaptureSession can set isRunning = false internally; mirror that
        // on the main thread so SwiftUI bindings update.
        DispatchQueue.main.async { self.isRunning = false }
    }

    @objc private func sessionInterruptionEnded() { start() }

    // MARK: - Lifecycle

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: - Helpers

    /// Re-sets the sample buffer delegate on `videoOutput`.
    /// Creates a fresh high-priority queue for frame delivery each time so
    /// queue state from a previous processor doesn't bleed through.
    private func rebindDelegate() {
        let frameQueue = DispatchQueue(label: "com.swingcap.camera.frames",
                                       qos: .userInteractive)
        videoOutput.setSampleBufferDelegate(frameProcessor, queue: frameQueue)
    }

    /// Finds the highest-resolution device format that meets the minimum
    /// width and frame-rate requirements.
    ///
    /// `device.formats` is ordered from lowest to highest quality, so
    /// iterating with `last { }` naturally picks the best match.
    private func findFormat(
        for device: AVCaptureDevice,
        minWidth: Int32,
        minFPS: Float64
    ) throws -> AVCaptureDevice.Format {
        let match = device.formats.last { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let fps = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return dims.width >= minWidth && fps >= minFPS
        }
        guard let match else { throw CameraError.noSuitableFormat }
        return match
    }
}

// MARK: - Errors

enum CameraError: LocalizedError {
    case deviceUnavailable
    case outputUnavailable
    case noSuitableFormat
    case bufferCopyFailed

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable:  "Camera device is not available."
        case .outputUnavailable:  "Could not configure video output."
        case .noSuitableFormat:   "No 60fps 1280p camera format found on this device."
        case .bufferCopyFailed:   "Failed to copy CMSampleBuffer into rolling buffer."
        }
    }
}
