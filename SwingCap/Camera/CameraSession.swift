import AVFoundation
import Observation
import UIKit

@Observable
final class CameraSession: NSObject {

    // MARK: - Public state

    var isRunning = false
    var error: CameraError?
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Private

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.swingcap.camera.session",
                                             qos: .userInteractive)

    var frameProcessor: FrameProcessor? {
        didSet { rebindDelegate() }
    }

    // MARK: - Setup

    func configure() throws {
        // Must not be called on sessionQueue — it's sync-dispatched below.
        try sessionQueue.sync { try self._configure() }
    }

    private func _configure() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .hd1280x720

        // Input
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                  for: .video,
                                                  position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else { throw CameraError.deviceUnavailable }
        captureSession.addInput(input)

        // 60 fps format
        let targetFormat = try findFormat(for: device, minWidth: 1280, minFPS: 60)
        try device.lockForConfiguration()
        device.activeFormat = targetFormat
        let frameDuration = CMTime(value: 1, timescale: 60)
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
        device.unlockForConfiguration()

        // Output
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        // Keep false so the rolling buffer never starves; revisit if memory
        // pressure becomes an issue.
        videoOutput.alwaysDiscardsLateVideoFrames = false

        guard captureSession.canAddOutput(videoOutput) else {
            throw CameraError.outputUnavailable
        }
        captureSession.addOutput(videoOutput)

        // Preview layer
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async { self.previewLayer = layer }

        rebindDelegate()
        subscribeToNotifications()
    }

    // MARK: - Notifications

    private func subscribeToNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(appWillResignActive),
                       name: UIApplication.willResignActiveNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(appDidBecomeActive),
                       name: UIApplication.didBecomeActiveNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(sessionWasInterrupted),
                       name: .AVCaptureSessionWasInterrupted,
                       object: captureSession)
        nc.addObserver(self,
                       selector: #selector(sessionInterruptionEnded),
                       name: .AVCaptureSessionInterruptionEnded,
                       object: captureSession)
    }

    @objc private func appWillResignActive() { stop() }

    @objc private func appDidBecomeActive() { start() }

    @objc private func sessionWasInterrupted() {
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

    private func rebindDelegate() {
        let frameQueue = DispatchQueue(label: "com.swingcap.camera.frames",
                                       qos: .userInteractive)
        videoOutput.setSampleBufferDelegate(frameProcessor, queue: frameQueue)
    }

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
