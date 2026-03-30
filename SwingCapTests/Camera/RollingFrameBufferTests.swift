import XCTest
import CoreMedia
import CoreVideo
import Darwin
@testable import SwingCap

final class RollingFrameBufferTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a minimal valid CMSampleBuffer backed by a blank CVPixelBuffer.
    private func makeSampleBuffer(presentationTime pts: CMTime = .zero) throws -> CMSampleBuffer {
        // Create a 4×4 pixel buffer (smallest valid size)
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 4, 4,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            throw XCTSkip("CVPixelBufferCreate failed — skipping on this platform")
        }

        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            formatDescriptionOut: &formatDesc
        )
        guard let fd = formatDesc else {
            throw XCTSkip("Could not create format description")
        }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            formatDescription: fd,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        guard let sb = sampleBuffer else {
            throw XCTSkip("Could not create sample buffer")
        }
        return sb
    }

    // MARK: - Tests

    func test_emptyBuffer_returnsZeroCount() {
        let buffer = RollingFrameBuffer(capacity: 10)
        XCTAssertEqual(buffer.frameCount, 0)
    }

    func test_snapshot_emptyBuffer_returnsEmptyArray() {
        let buffer = RollingFrameBuffer(capacity: 10)
        XCTAssertTrue(buffer.snapshot().isEmpty)
    }

    func test_append_incrementsCount() throws {
        let buffer = RollingFrameBuffer(capacity: 10)
        try buffer.append(makeSampleBuffer())
        XCTAssertEqual(buffer.frameCount, 1)
    }

    func test_append_doesNotExceedCapacity() throws {
        let capacity = 5
        let buffer = RollingFrameBuffer(capacity: capacity)
        for i in 0..<(capacity + 3) {
            try buffer.append(makeSampleBuffer(presentationTime: CMTime(value: CMTimeValue(i), timescale: 60)))
        }
        XCTAssertEqual(buffer.frameCount, capacity)
    }

    func test_snapshot_returnsChronologicalOrder() throws {
        let buffer = RollingFrameBuffer(capacity: 10)
        let times = (0..<5).map { CMTime(value: CMTimeValue($0), timescale: 60) }
        for t in times {
            try buffer.append(makeSampleBuffer(presentationTime: t))
        }

        let frames = buffer.snapshot()
        XCTAssertEqual(frames.count, 5)

        let pts = frames.map { CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp($0)) }
        XCTAssertEqual(pts, pts.sorted(), "Frames must be in ascending timestamp order")
    }

    func test_snapshot_afterWrapAround_remainsChronological() throws {
        let capacity = 4
        let buffer = RollingFrameBuffer(capacity: capacity)
        // Write 7 frames — wraps around once
        for i in 0..<7 {
            try buffer.append(makeSampleBuffer(presentationTime: CMTime(value: CMTimeValue(i), timescale: 60)))
        }

        let frames = buffer.snapshot()
        XCTAssertEqual(frames.count, capacity)

        let pts = frames.map { CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp($0)) }
        XCTAssertEqual(pts, pts.sorted(), "Frames after wrap must still be chronological")
        // Oldest retained frame should be frame 3 (7 - capacity = 3)
        XCTAssertEqual(pts.first!, 3.0 / 60.0, accuracy: 0.0001)
    }

    func test_clear_resetsBuffer() throws {
        let buffer = RollingFrameBuffer(capacity: 10)
        for i in 0..<5 {
            try buffer.append(makeSampleBuffer(presentationTime: CMTime(value: CMTimeValue(i), timescale: 60)))
        }
        buffer.clear()
        XCTAssertEqual(buffer.frameCount, 0)
        XCTAssertTrue(buffer.snapshot().isEmpty)
    }

    func test_snapshot_doesNotClearBuffer() throws {
        let buffer = RollingFrameBuffer(capacity: 10)
        try buffer.append(makeSampleBuffer())
        _ = buffer.snapshot()
        XCTAssertEqual(buffer.frameCount, 1)
    }

    /// Creates a 1280×720 pixel buffer to simulate real capture frames.
    private func makeLargeSampleBuffer(presentationTime pts: CMTime = .zero) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 1280, 720,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            throw XCTSkip("CVPixelBufferCreate (large) failed — skipping on this platform")
        }

        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            formatDescriptionOut: &formatDesc
        )
        guard let fd = formatDesc else { throw XCTSkip("Format description unavailable") }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            formatDescription: fd,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        guard let sb = sampleBuffer else { throw XCTSkip("Could not create large sample buffer") }
        return sb
    }

    /// Fills the buffer to 2× capacity with full 1280×720 frames and verifies
    /// the retained count never exceeds `capacity` (eviction is working).
    func test_memoryPressure_frameCountNeverExceedsCapacity() throws {
        let capacity = RollingFrameBuffer.defaultCapacity   // 120
        let buffer = RollingFrameBuffer(capacity: capacity)

        for i in 0..<(capacity * 2) {
            let frame = try makeLargeSampleBuffer(
                presentationTime: CMTime(value: CMTimeValue(i), timescale: 60)
            )
            buffer.append(frame)
            XCTAssertLessThanOrEqual(
                buffer.frameCount, capacity,
                "Frame count exceeded capacity at append \(i)"
            )
        }

        XCTAssertEqual(buffer.frameCount, capacity)

        // Verify most-recent frames are retained
        let snap = buffer.snapshot()
        let lastPTS = CMTimeGetSeconds(
            CMSampleBufferGetPresentationTimeStamp(snap.last!)
        )
        let expectedLastPTS = Double(capacity * 2 - 1) / 60.0
        XCTAssertEqual(lastPTS, expectedLastPTS, accuracy: 0.0001)
    }

    /// Peak memory growth while filling the buffer should stay below 250 MB
    /// (120 frames × ~1.38 MB per 720p YCbCr frame ≈ 166 MB, with headroom).
    func test_memoryPressure_peakMemoryWithinBudget() throws {
        let capacity = RollingFrameBuffer.defaultCapacity
        let budgetBytes: Int64 = 250 * 1024 * 1024   // 250 MB

        var peakDelta: Int64 = 0
        let baselineBytes = currentMemoryBytes()

        let buffer = RollingFrameBuffer(capacity: capacity)
        for i in 0..<(capacity * 2) {
            if let frame = try? makeLargeSampleBuffer(
                presentationTime: CMTime(value: CMTimeValue(i), timescale: 60)
            ) {
                buffer.append(frame)
                let delta = currentMemoryBytes() - baselineBytes
                if delta > peakDelta { peakDelta = delta }
            }
        }

        XCTAssertLessThanOrEqual(
            peakDelta, budgetBytes,
            "Rolling buffer peak memory \(peakDelta / 1024 / 1024) MB exceeded budget of \(budgetBytes / 1024 / 1024) MB"
        )
    }

    /// Returns the current resident memory of the test process in bytes.
    private func currentMemoryBytes() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }

    func test_concurrentAppends_doNotCrash() throws {
        let buffer = RollingFrameBuffer(capacity: 50)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 0..<100 {
            group.enter()
            queue.async {
                let t = CMTime(value: CMTimeValue(i), timescale: 60)
                if let sb = try? self.makeSampleBuffer(presentationTime: t) {
                    buffer.append(sb)
                }
                group.leave()
            }
        }

        group.wait()
        XCTAssertLessThanOrEqual(buffer.frameCount, 50)
    }
}
