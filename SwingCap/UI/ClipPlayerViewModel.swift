import AVFoundation
import Observation

/// Owns the `AVPlayer` and all playback state for `ClipPlayerView`.
/// Drives the scrubber, speed, loop, and frame-step controls.
///
/// ## Scrubber vs. time observer
///
/// `AVPlayer` fires a periodic time observer at ~60fps to keep `currentTime`
/// in sync with playback. When the user drags the scrubber, there is a
/// potential write-back conflict: the time observer tries to set `currentTime`
/// while the scrubber is also setting it. This causes the scrubber to jump.
///
/// The fix is the `isScrubbing` flag:
/// - Set `true` in `scrubBegan()` — time observer stops updating `currentTime`.
/// - Set `false` in the `scrubEnded` completion callback — only after the
///   final accurate seek completes does the observer resume.
///
/// ## Seek tolerance
///
/// `scrubChanged` uses a loose tolerance (±100ms) for the live drag because
/// fast-path seeks in `AVPlayer` are cheap and we don't need frame-accurate
/// positioning during the drag gesture.
///
/// `scrubEnded` uses zero tolerance so the final resting position is exactly
/// on the requested frame — important when stepping frame-by-frame.
///
/// ## Loop
///
/// `AVPlayerItemDidPlayToEndTime` notification drives looping. When `isLooping`
/// is `true`, the handler seeks to `.zero` and calls `play()` then restores
/// `playbackRate` (because `play()` always sets rate to 1.0).
@Observable
final class ClipPlayerViewModel {

    // MARK: - Playback state

    /// Current playback position in seconds; bound to the scrubber slider.
    var currentTime: Double = 0
    /// Total clip duration in seconds; loaded asynchronously from `AVAsset`.
    var duration: Double = 0
    var isPlaying: Bool = false
    /// When `true`, the periodic time observer skips writing `currentTime` so
    /// it doesn't fight the scrubber during a drag gesture.
    var isScrubbing: Bool = false
    var playbackRate: Float = 1.0
    var isLooping: Bool = true

    // MARK: - Player

    let player: AVPlayer

    // MARK: - Private

    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private let clip: Clip

    // MARK: - Init / deinit

    init(clip: Clip) {
        self.clip = clip
        self.player = AVPlayer(url: clip.url)
        setupTimeObserver()
        setupEndObserver()
        // Duration is not immediately available — `AVAsset.load(.duration)` is
        // async to avoid blocking the main thread on a file stat.
        Task { await loadDuration() }
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Transport controls

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            // `play()` resets rate to 1.0 internally, so we must restore
            // the user's chosen speed immediately after.
            player.rate = playbackRate
            isPlaying = true
        }
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player.rate = rate }
    }

    /// Advances one video frame forward.
    func stepForward() {
        player.currentItem?.step(byCount: 1)
    }

    /// Steps one video frame backward.
    func stepBack() {
        player.currentItem?.step(byCount: -1)
    }

    /// Called when the scrubber drag begins.
    /// Sets `isScrubbing = true` to suppress time-observer write-back.
    func scrubBegan() {
        isScrubbing = true
    }

    /// Called continuously as the user drags — uses loose seek tolerance
    /// (±100ms) for a responsive feel without burning CPU on accurate seeks.
    func scrubChanged(to time: Double) {
        currentTime = time
        player.seek(
            to: CMTime(seconds: time, preferredTimescale: 600),
            toleranceBefore: CMTime(value: 1, timescale: 10),
            toleranceAfter:  CMTime(value: 1, timescale: 10)
        )
    }

    /// Called when the drag ends — performs a zero-tolerance seek for
    /// frame-accurate positioning, then re-enables the time observer.
    func scrubEnded(at time: Double) {
        currentTime = time
        player.seek(
            to: CMTime(seconds: time, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            // Clear the flag inside the completion so the observer only
            // resumes after the accurate seek has landed.
            self?.isScrubbing = false
        }
    }

    // MARK: - Private setup

    /// Registers a periodic time observer at 1/60s intervals on the main queue.
    /// The `isScrubbing` guard prevents it from overwriting the scrubber position
    /// while the user is dragging.
    private func setupTimeObserver() {
        let interval = CMTime(value: 1, timescale: 60)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            self.currentTime = CMTimeGetSeconds(time)
            // Derive `isPlaying` from the actual player rate rather than
            // maintaining a separate flag that could drift out of sync.
            self.isPlaying = (self.player.rate != 0)
        }
    }

    /// Observes `AVPlayerItemDidPlayToEndTime` to implement looping.
    private func setupEndObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.isLooping {
                self.player.seek(to: .zero)
                self.player.play()
                // Restore the user's chosen speed — `play()` resets to 1.0.
                self.player.rate = self.playbackRate
            } else {
                self.isPlaying = false
            }
        }
    }

    /// Asynchronously loads the clip's duration from `AVAsset`.
    /// Using the modern async API avoids the blocking `asset.duration` property.
    @MainActor
    private func loadDuration() async {
        let asset = AVAsset(url: clip.url)
        guard let d = try? await asset.load(.duration) else { return }
        duration = CMTimeGetSeconds(d)
    }
}
