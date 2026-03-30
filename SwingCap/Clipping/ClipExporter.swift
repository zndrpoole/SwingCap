import AVFoundation
import CoreImage
import UIKit

/// Converts an ordered array of `CMSampleBuffer` frames into an H.264 MP4
/// file and returns a `Clip` value with the file URL and a thumbnail.
///
/// Isolated to an `actor` so callers don't need to think about threading;
/// file I/O and encoding happen off the main thread automatically.
actor ClipExporter {

    // MARK: - Configuration

    private static let targetBitrate = 6_000_000   // 6 Mbps — good for 720p/60
    private let outputDirectory: URL

    // MARK: - Init

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                             in: .userDomainMask)[0]
        outputDirectory = docs.appendingPathComponent("SwingCap/Clips",
                                                       isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDirectory,
                                                 withIntermediateDirectories: true)
    }

    // MARK: - Export

    /// Encodes `frames` into an MP4 and returns a `Clip`.
    /// - Throws: `ExportError` if encoding fails.
    func export(frames: [CMSampleBuffer]) async throws -> Clip {
        guard let firstFrame = frames.first else { throw ExportError.noFrames }

        let outputURL = outputDirectory.appendingPathComponent("\(UUID().uuidString).mp4")

        let (width, height) = dimensions(of: firstFrame)
        let writer = try makeWriter(outputURL: outputURL)
        let (input, adaptor) = makeVideoInput(width: width, height: height)

        writer.add(input)
        writer.startWriting()

        let baseTime = CMSampleBufferGetPresentationTimeStamp(firstFrame)
        writer.startSession(atSourceTime: .zero)

        for frame in frames {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(frame) else { continue }

            // Spin until the input is ready; yields to the Swift concurrency
            // scheduler each iteration so we don't block other tasks.
            while !input.isReadyForMoreMediaData { await Task.yield() }

            let pts = CMSampleBufferGetPresentationTimeStamp(frame)
            let relativePTS = CMTimeSubtract(pts, baseTime)
            adaptor.append(pixelBuffer, withPresentationTime: relativePTS)
        }

        input.markAsFinished()
        await finishWriting(writer)

        if writer.status == .failed {
            throw ExportError.writingFailed(writer.error)
        }

        let thumbnail = makeThumbnail(from: frames[frames.count / 2])
        let duration = clipDuration(frames: frames)
        return Clip(url: outputURL, thumbnail: thumbnail, duration: duration)
    }

    // MARK: - Helpers

    private func makeWriter(outputURL: URL) throws -> AVAssetWriter {
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw ExportError.writerCreationFailed
        }
        return writer
    }

    private func makeVideoInput(
        width: Int, height: Int
    ) -> (AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor) {
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Self.targetBitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: nil
        )
        return (input, adaptor)
    }

    private func finishWriting(_ writer: AVAssetWriter) async {
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
    }

    private func dimensions(of sampleBuffer: CMSampleBuffer) -> (Int, Int) {
        guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return (1280, 720) }
        return (CVPixelBufferGetWidth(buf), CVPixelBufferGetHeight(buf))
    }

    private func clipDuration(frames: [CMSampleBuffer]) -> TimeInterval {
        guard frames.count >= 2 else { return 0 }
        let start = CMSampleBufferGetPresentationTimeStamp(frames.first!)
        let end   = CMSampleBufferGetPresentationTimeStamp(frames.last!)
        return CMTimeGetSeconds(CMTimeSubtract(end, start))
    }

    private func makeThumbnail(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Errors

extension ClipExporter {
    enum ExportError: LocalizedError {
        case noFrames
        case writerCreationFailed
        case writingFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .noFrames:              "No frames provided for export."
            case .writerCreationFailed:  "Failed to create AVAssetWriter."
            case .writingFailed(let e):  "Encoding failed: \(e?.localizedDescription ?? "unknown")"
            }
        }
    }
}
