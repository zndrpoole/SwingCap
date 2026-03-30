import AVFoundation
import Observation

/// Owns the `AVPlayer` and all playback state for `ClipPlayerView`.
/// Drives the scrubber, speed, loop, and frame-step controls.
@Observable
final class ClipPlayerViewModel {

    // MARK: - Playback state

    var currentTime: Double = 0       // seconds, bound to scrubber
    var duration: Double = 0          // seconds, loaded async
    var isPlaying: Bool = false
    var isScrubbing: Bool = false      // suppresses time-observer write-back
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
            player.rate = playbackRate   // restore speed after play resets it
            isPlaying = true
        }
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player.rate = rate }
    }

    func stepForward() {
        player.currentItem?.step(byCount: 1)
    }

    func stepBack() {
        player.currentItem?.step(byCount: -1)
    }

    /// Called when the scrubber drag begins.
    func scrubBegan() {
        isScrubbing = true
    }

    /// Called continuously during drag — uses loose tolerance for performance.
    func scrubChanged(to time: Double) {
        currentTime = time
        player.seek(
            to: CMTime(seconds: time, preferredTimescale: 600),
            toleranceBefore: CMTime(value: 1, timescale: 10),
            toleranceAfter:  CMTime(value: 1, timescale: 10)
        )
    }

    /// Called when drag ends — accurate seek to the final position.
    func scrubEnded(at time: Double) {
        currentTime = time
        player.seek(
            to: CMTime(seconds: time, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            self?.isScrubbing = false
        }
    }

    // MARK: - Private setup

    private func setupTimeObserver() {
        let interval = CMTime(value: 1, timescale: 60)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            self.currentTime = CMTimeGetSeconds(time)
            self.isPlaying = (self.player.rate != 0)
        }
    }

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
                self.player.rate = self.playbackRate
            } else {
                self.isPlaying = false
            }
        }
    }

    @MainActor
    private func loadDuration() async {
        let asset = AVAsset(url: clip.url)
        guard let d = try? await asset.load(.duration) else { return }
        duration = CMTimeGetSeconds(d)
    }
}
