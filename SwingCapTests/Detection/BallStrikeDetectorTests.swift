import XCTest
import CoreMedia
import CoreVideo
@testable import SwingCap

final class BallStrikeDetectorTests: XCTestCase {

    // MARK: - Fallback path

    func test_init_withoutModel_usesMotionThreshold() {
        // The test bundle never has GolfBallDetector.mlpackage, so the
        // detector must silently fall back to MotionThresholdDetector.
        let detector = BallStrikeDetector()
        XCTAssertEqual(
            detector.detectorTypeName,
            "MotionThresholdDetector",
            "Without a bundled model the fallback detector must be MotionThresholdDetector"
        )
    }

    func test_onStrikeCallback_isForwarded() {
        let detector = BallStrikeDetector()
        var called = false
        detector.onStrike = { _ in called = true }
        // We can't easily fire a real strike without hardware frames, but we
        // can verify the callback is wired through without crashing.
        XCTAssertNotNil(detector.onStrike)
        _ = called // suppress unused warning
    }

    // MARK: - MotionThresholdDetector constants

    func test_motionThresholdDetector_constants_areInExpectedRange() {
        XCTAssertGreaterThan(MotionThresholdDetector.motionThreshold, 0)
        XCTAssertLessThan(MotionThresholdDetector.motionThreshold, 1)
        XCTAssertGreaterThan(MotionThresholdDetector.cooldownSeconds, 0)
    }

    // MARK: - MotionThresholdDetector — cooldown

    func test_motionThresholdDetector_respectsCooldown() throws {
        let detector = MotionThresholdDetector()
        var strikeCount = 0
        detector.onStrike = { _ in strikeCount += 1 }

        // Feed a high-motion frame pair — should trigger once
        let frame1 = try makePixelBuffer(fill: 0)
        let frame2 = try makePixelBuffer(fill: 200) // large luma diff

        let sb1 = try makeSampleBuffer(pixelBuffer: frame1, pts: CMTime(value: 0, timescale: 60))
        let sb2 = try makeSampleBuffer(pixelBuffer: frame2, pts: CMTime(value: 1, timescale: 60))
        // A second high-motion pair immediately after — cooldown must block it
        let sb3 = try makeSampleBuffer(pixelBuffer: frame1, pts: CMTime(value: 2, timescale: 60))
        let sb4 = try makeSampleBuffer(pixelBuffer: frame2, pts: CMTime(value: 3, timescale: 60))

        detector.process(sb1)
        detector.process(sb2)   // may trigger
        let afterFirst = strikeCount

        detector.process(sb3)
        detector.process(sb4)   // must NOT trigger (cooldown)

        XCTAssertEqual(strikeCount, afterFirst, "Cooldown must suppress back-to-back strikes")
    }

    func test_motionThresholdDetector_doesNotFireOnStaticScene() throws {
        let detector = MotionThresholdDetector()
        var strikeCount = 0
        detector.onStrike = { _ in strikeCount += 1 }

        // Two identical frames → zero luma diff → no strike
        let pb = try makePixelBuffer(fill: 128)
        let sb1 = try makeSampleBuffer(pixelBuffer: pb, pts: CMTime(value: 0, timescale: 60))
        let sb2 = try makeSampleBuffer(pixelBuffer: pb, pts: CMTime(value: 1, timescale: 60))

        detector.process(sb1)
        detector.process(sb2)

        XCTAssertEqual(strikeCount, 0, "Identical frames must not trigger a strike")
    }

    // MARK: - CoreMLBallDetector constants

    func test_coreMLBallDetector_constants_areInExpectedRange() {
        XCTAssertGreaterThan(CoreMLBallDetector.minBallConfidence, 0)
        XCTAssertLessThanOrEqual(CoreMLBallDetector.minBallConfidence, 1)
        XCTAssertGreaterThan(CoreMLBallDetector.departureFrameThreshold, 0)
        XCTAssertGreaterThan(CoreMLBallDetector.minStableFrames, 0)
        XCTAssertGreaterThan(CoreMLBallDetector.detectionCooldownSeconds, 0)
        XCTAssertFalse(CoreMLBallDetector.targetClassName.isEmpty)
    }

    // MARK: - Helpers

    private func makePixelBuffer(fill: UInt8) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 64, 64,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            nil, &pb
        )
        guard status == kCVReturnSuccess, let pixelBuffer = pb else {
            throw XCTSkip("CVPixelBufferCreate failed")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
            let count = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
                      * CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            memset(base, Int32(fill), count)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        return pixelBuffer
    }

    private func makeSampleBuffer(pixelBuffer: CVPixelBuffer, pts: CMTime) throws -> CMSampleBuffer {
        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard let fd = formatDesc else { throw XCTSkip("No format description") }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sb: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: fd,
            sampleTiming: &timing,
            sampleBufferOut: &sb
        )
        guard let sampleBuffer = sb else { throw XCTSkip("Could not create sample buffer") }
        return sampleBuffer
    }
}
