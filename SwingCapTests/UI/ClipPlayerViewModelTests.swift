import XCTest
import AVFoundation
@testable import SwingCap

final class ClipPlayerViewModelTests: XCTestCase {

    // MARK: - Helpers

    /// Returns the URL of a silent test video bundled in the test target,
    /// or skips the test if none is present.
    private func testVideoURL() throws -> URL {
        // Look for any .mp4 in the test bundle
        if let url = Bundle(for: Self.self).url(forResource: "test_clip", withExtension: "mp4") {
            return url
        }
        // Fall back to a system sound file that AVPlayer can open (no video but valid media)
        let sysSound = URL(fileURLWithPath: "/System/Library/Audio/UISounds/begin_record.caf")
        if FileManager.default.fileExists(atPath: sysSound.path) { return sysSound }
        throw XCTSkip("No test media available — add test_clip.mp4 to SwingCapTests/Resources")
    }

    private func makeClip(url: URL, duration: TimeInterval = 3.0) -> Clip {
        Clip(url: url, thumbnail: nil, duration: duration)
    }

    // MARK: - Initialisation

    func test_init_defaultState() throws {
        let url = try testVideoURL()
        let vm = ClipPlayerViewModel(clip: makeClip(url: url))

        XCTAssertFalse(vm.isPlaying)
        XCTAssertFalse(vm.isScrubbing)
        XCTAssertFalse(vm.isLooping)  // starts unlooped; review UX sets default
        XCTAssertEqual(vm.currentTime, 0, accuracy: 0.01)
        XCTAssertEqual(vm.playbackRate, 1.0)
        XCTAssertNotNil(vm.player)
    }

    // MARK: - Rate control

    func test_setRate_updatesPlaybackRate() throws {
        let vm = ClipPlayerViewModel(clip: makeClip(url: try testVideoURL()))
        vm.setRate(0.25)
        XCTAssertEqual(vm.playbackRate, 0.25)
    }

    func test_setRate_doesNotChangePlayerRateWhenPaused() throws {
        let vm = ClipPlayerViewModel(clip: makeClip(url: try testVideoURL()))
        vm.setRate(0.5)
        // Player should still be paused (rate 0) since we never called play
        XCTAssertEqual(vm.player.rate, 0.0, "Paused player rate must stay 0 when only playbackRate changes")
    }

    // MARK: - Scrubbing

    func test_scrubBegan_setsScrubbing() throws {
        let vm = ClipPlayerViewModel(clip: makeClip(url: try testVideoURL()))
        vm.scrubBegan()
        XCTAssertTrue(vm.isScrubbing)
    }

    func test_scrubEnded_clearsScrubbing() throws {
        let vm = ClipPlayerViewModel(clip: makeClip(url: try testVideoURL()))
        vm.scrubBegan()
        vm.scrubEnded(at: 0)
        // isScrubbing is cleared inside the seek completion handler; allow a brief wait
        let expectation = XCTestExpectation(description: "scrubbing cleared")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertFalse(vm.isScrubbing)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.5)
    }

    func test_scrubChanged_updatesCurrentTime() throws {
        let vm = ClipPlayerViewModel(clip: makeClip(url: try testVideoURL(), duration: 3.0))
        vm.scrubBegan()
        vm.scrubChanged(to: 1.5)
        XCTAssertEqual(vm.currentTime, 1.5, accuracy: 0.01)
    }

    // MARK: - Loop toggle

    func test_loopToggle_flipsState() throws {
        let vm = ClipPlayerViewModel(clip: makeClip(url: try testVideoURL()))
        let initial = vm.isLooping
        vm.isLooping.toggle()
        XCTAssertNotEqual(vm.isLooping, initial)
    }

    // MARK: - Play / pause

    func test_togglePlayPause_changesIsPlaying() throws {
        let vm = ClipPlayerViewModel(clip: makeClip(url: try testVideoURL()))
        XCTAssertFalse(vm.isPlaying)
        vm.togglePlayPause()
        XCTAssertTrue(vm.isPlaying)
        vm.togglePlayPause()
        XCTAssertFalse(vm.isPlaying)
    }
}
