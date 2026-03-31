import AVFoundation
import Photos
import SwiftUI

/// Full-screen video player for reviewing a single swing clip.
///
/// ## Controls
/// - Speed buttons (0.25×, 0.5×, 1×) — change `ClipPlayerViewModel.playbackRate`.
/// - Scrubber slider — drag to scrub; see `ClipPlayerViewModel` for how the
///   `isScrubbing` flag prevents the time observer from fighting the drag.
/// - Frame step buttons — use `AVPlayerItem.step(byCount:)` for frame accuracy.
/// - Loop toggle — handled by `ClipPlayerViewModel`'s end-of-item notification.
///
/// ## Share to Photos
/// Calls `PHPhotoLibrary.requestAuthorization(for: .addOnly)` then
/// `PHAssetChangeRequest.creationRequestForAssetFromVideo`. The result
/// is shown as an animated toast that auto-dismisses after 2.5 seconds.
///
/// ## Notes
/// A single-line `TextField` at the bottom of the controls panel lets the user
/// annotate the clip. Notes are loaded from `SessionStore` on appear and saved
/// back on dismiss or when the user submits the text field.
struct ClipPlayerView: View {

    let clip: Clip
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @State private var vm: ClipPlayerViewModel
    @State private var exportState: ExportState = .idle
    /// In-flight notes text bound to the notes `TextField`.
    @State private var notes: String = ""
    @FocusState private var notesFocused: Bool

    private enum ExportState {
        case idle, saving, saved, failed
    }

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
        .overlay(alignment: .topTrailing) { topTrailingButtons }
        .overlay(alignment: .top) { exportToast }
        .preferredColorScheme(.dark)
        // Load persisted notes when the player appears.
        .onAppear { notes = sessionStore.notes(for: clip) ?? "" }
        .onDisappear {
            vm.player.pause()
            // Persist any unsaved notes when the player is dismissed.
            saveNotes()
        }
    }

    // MARK: - Controls panel

    private var controls: some View {
        VStack(spacing: 12) {
            speedButtons
            scrubber
            transportRow
            notesField
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
                // `editing` is `true` when drag starts, `false` when it ends.
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
            // Step back one video frame
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

            // Step forward one video frame
            Button { vm.stepForward() } label: {
                Image(systemName: "forward.frame.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer()

            // Loop toggle — highlights when active
            Button { vm.isLooping.toggle() } label: {
                Image(systemName: "repeat")
                    .font(.body)
                    .foregroundStyle(vm.isLooping ? .white : .white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 4)
    }

    /// Single-line text field for annotating the clip.
    /// Auto-saves on submit (keyboard return) and on player dismiss.
    private var notesField: some View {
        TextField("Add a note…", text: $notes)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .focused($notesFocused)
            .submitLabel(.done)
            .onSubmit { saveNotes() }
            .tint(.white)
    }

    // MARK: - Top-trailing buttons (dismiss + share)

    private var topTrailingButtons: some View {
        HStack(spacing: 12) {
            // Share / Save to Photos
            Button {
                saveToPhotos()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(exportState == .saving ? .gray : .white)
            }
            .buttonStyle(.plain)
            .disabled(exportState == .saving)

            // Dismiss
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 56)
        .padding(.trailing, 20)
    }

    private var exportToast: some View {
        Group {
            switch exportState {
            case .saved:
                Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.green.opacity(0.85), in: Capsule())
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            case .failed:
                Label("Save failed", systemImage: "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.85), in: Capsule())
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            default:
                EmptyView()
            }
        }
        .animation(.spring(duration: 0.3), value: exportState == .saved || exportState == .failed)
    }

    // MARK: - Notes

    /// Writes the current `notes` string to the matching `PersistedClip` record
    /// via `SessionStore`. Silently no-ops if the clip has no persisted record
    /// (e.g. the `/dev/null` debug placeholder).
    private func saveNotes() {
        sessionStore.updateNotes(notes, for: clip)
    }

    // MARK: - Save to Photos

    /// Requests `.addOnly` photo library authorization then adds the clip's
    /// MP4 file as a video asset. The result is reflected in `exportState`
    /// which drives the toast overlay.
    private func saveToPhotos() {
        guard exportState != .saving else { return }
        exportState = .saving

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.exportState = .failed }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.clip.url)
            }) { success, _ in
                DispatchQueue.main.async {
                    self.exportState = success ? .saved : .failed
                    // Auto-clear the toast after 2.5 s so it doesn't linger.
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2.5))
                        if self.exportState == .saved || self.exportState == .failed {
                            self.exportState = .idle
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
