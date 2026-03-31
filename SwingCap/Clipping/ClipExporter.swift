import AVFoundation
import CoreImage
import UIKit

/// Converts an ordered array of `CMSampleBuffer` frames into an H.264 MP4
/// file and returns a `Clip` value with the file URL and a thumbnail.
///
/// ## How encoding works
///
/// 1. Create an `AVAssetWriter` targeting a new UUID-named `.mp4` file.
/// 2. Add one `AVAssetWriterInput` configured for H.264 at 6 Mbps.
/// 3. Re-time frames: subtract the first frame's PTS from all timestamps so
///    the clip starts at t = 0 in the output file (required by `AVAssetWriter`).
/// 4. Feed pixel buffers through an `AVAssetWriterInputPixelBufferAdaptor`,
///    yielding with `Task.yield()` when the input is back-pressured.
/// 5. Extract a thumbnail from the middle frame via `CIContext`.
///
/// ## Thread safety
/// Isolated to an `actor` so callers don't need to think about threading;
/// all file I/O and encoding happen off the main thread automatically.
///
/// ## Storage guard
/// Before writing, the exporter checks available disk space. If fewer than
/// `minimumFreeSpaceBytes` (50 MB) are available it throws
/// `ExportError.insufficientStorage` rather than starting a write that would
/// likely fail mid-way and leave a corrupt file on disk.
actor ClipExporter {

    // MARK: - Configuration

    /// Target video bitrate (6 Mbps is a good balance of quality vs. file size
    /// for 720p/60fps — a 3-second clip is roughly 2.25 MB).
    private static let targetBitrate = 6_000_000
    /// Refuse to start a new export if free disk space falls below this threshold (50 MB).
    private static let minimumFreeSpaceBytes: Int64 = 50 * 1024 * 1024
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
    ///
    /// - Parameters:
    ///   - frames: Ordered array of captured frames (~180 at 60fps).
    ///   - onProgress: Optional closure called with progress in [0, 1] as
    ///                 frames are encoded. Called inside the actor (not on
    ///                 the main thread) — callers must dispatch to main if
    ///                 updating UI.
    /// - Throws: `ExportError` if storage is low, the writer can't be created,
    ///           or encoding fails.
    func export(
        frames: [CMSampleBuffer],
        onProgress: ((Float) -> Void)? = nil
    ) async throws -> Clip {
        guard let firstFrame = frames.first else { throw ExportError.noFrames }

        // Guard against writing when storage is critically low to avoid
        // leaving a partial/corrupt file on disk.
        if let freeSpace = try? outputDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
                                               .volumeAvailableCapacity,
           Int64(freeSpace) < Self.minimumFreeSpaceBytes {
            throw ExportError.insufficientStorage
        }

        let outputURL = outputDirectory.appendingPathComponent("\(UUID().uuidString).mp4")

        let (width, height) = dimensions(of: firstFrame)
        let writer = try makeWriter(outputURL: outputURL)
        let (input, adaptor) = makeVideoInput(width: width, height: height)

        writer.add(input)
        writer.startWriting()

        // All frames are re-timed relative to the first frame so the clip
        // starts at t=0 in the output file. `AVAssetWriter` requires this;
        // it does not accept sessions starting at an arbitrary wall-clock time.
        let baseTime = CMSampleBufferGetPresentationTimeStamp(firstFrame)
        writer.startSession(atSourceTime: .zero)

        let total = frames.count
        for (index, frame) in frames.enumerated() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(frame) else { continue }

            // Back-pressure: `AVAssetWriterInput` signals readiness asynchronously.
            // Yield to the Swift concurrency scheduler each spin so we don't
            // block other tasks on this actor while waiting.
            while !input.isReadyForMoreMediaData { await Task.yield() }

            let pts = CMSampleBufferGetPresentationTimeStamp(frame)
            let relativePTS = CMTimeSubtract(pts, baseTime)
            adaptor.append(pixelBuffer, withPresentationTime: relativePTS)

            onProgress?(Float(index + 1) / Float(total))
        }

        input.markAsFinished()
        await finishWriting(writer)

        if writer.status == .failed {
            throw ExportError.writingFailed(writer.error)
        }

        // Use the middle frame for the thumbnail — it's most representative
        // of the swing at its midpoint rather than the pre-impact setup.
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
        // `false` here because we are feeding pre-captured frames in a tight loop,
        // not encoding live camera data — we can wait for the encoder to be ready.
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: nil
        )
        return (input, adaptor)
    }

    /// Wraps `AVAssetWriter.finishWriting` in a continuation so we can `await` it.
    private func finishWriting(_ writer: AVAssetWriter) async {
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
    }

    private func dimensions(of sampleBuffer: CMSampleBuffer) -> (Int, Int) {
        guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return (1280, 720) }
        return (CVPixelBufferGetWidth(buf), CVPixelBufferGetHeight(buf))
    }

    /// Calculates clip duration from the PTS spread of the first and last frames.
    private func clipDuration(frames: [CMSampleBuffer]) -> TimeInterval {
        guard frames.count >= 2 else { return 0 }
        let start = CMSampleBufferGetPresentationTimeStamp(frames.first!)
        let end   = CMSampleBufferGetPresentationTimeStamp(frames.last!)
        return CMTimeGetSeconds(CMTimeSubtract(end, start))
    }

    /// Renders the Y'CbCr pixel buffer through `CIContext` to produce a
    /// `UIImage` thumbnail. Uses the GPU-backed context (`useSoftwareRenderer: false`)
    /// for speed.
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
        case insufficientStorage

        var errorDescription: String? {
            switch self {
            case .noFrames:              "No frames provided for export."
            case .writerCreationFailed:  "Failed to create AVAssetWriter."
            case .writingFailed(let e):  "Encoding failed: \(e?.localizedDescription ?? "unknown")"
            case .insufficientStorage:   "Not enough free storage to save this clip (need at least 50 MB)."
            }
        }
    }
}
