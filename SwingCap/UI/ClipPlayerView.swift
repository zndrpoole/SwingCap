import AVFoundation
import SwiftUI

/// Full-screen video player for reviewing a single swing clip.
/// Controls: speed (0.25×/0.5×/1×), scrubber, frame-step, loop toggle.
struct ClipPlayerView: View {

    let clip: Clip
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ClipPlayerViewModel

    init(clip: Clip) {
        self.clip = clip
        _vm = State(initialValue: ClipPlayerViewModel(clip: clip))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            VideoPlayerView(player: vm.player)
                .ignoresSafeArea()
                .onTapGesture { vm.togglePlayPause() }

            controls
        }
        .overlay(alignment: .topTrailing) { dismissButton }
        .preferredColorScheme(.dark)
        .onDisappear { vm.player.pause() }
    }

    // MARK: - Controls panel

    private var controls: some View {
        VStack(spacing: 12) {
            speedButtons
            scrubber
            transportRow
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    private var speedButtons: some View {
        HStack(spacing: 12) {
            ForEach([Float(0.25), 0.5, 1.0], id: \.self) { rate in
                Button {
                    vm.setRate(rate)
                } label: {
                    Text(rate == 1.0 ? "1×" : "\(rate, specifier: "%.2g")×")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(vm.playbackRate == rate ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            vm.playbackRate == rate ? Color.white : Color.white.opacity(0.15),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(String(format: "%.1fs", clip.duration))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { vm.currentTime },
                    set: { vm.scrubChanged(to: $0) }
                ),
                in: 0...max(vm.duration, 0.001)
            ) { editing in
                if editing { vm.scrubBegan() }
                else { vm.scrubEnded(at: vm.currentTime) }
            }
            .tint(.white)

            HStack {
                Text(formatTime(vm.currentTime))
                Spacer()
                Text(formatTime(vm.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var transportRow: some View {
        HStack(spacing: 32) {
            // Step back
            Button { vm.stepBack() } label: {
                Image(systemName: "backward.frame.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            // Play / Pause
            Button { vm.togglePlayPause() } label: {
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            // Step forward
            Button { vm.stepForward() } label: {
                Image(systemName: "forward.frame.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer()

            // Loop toggle
            Button { vm.isLooping.toggle() } label: {
                Image(systemName: "repeat")
                    .font(.body)
                    .foregroundStyle(vm.isLooping ? .white : .white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .padding(.top, 56)
        .padding(.trailing, 20)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
