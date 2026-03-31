import Foundation
import Observation
import UIKit

/// Represents one driving-range session and the clips captured during it.
///
/// **Lifecycle**: Created fresh each time the user opens `SessionView`. Clips
/// accumulate as swings are detected. The session object lives for the
/// duration of the active screen; `SessionStore` handles long-term persistence.
///
/// **Export flow**: `handleFrameWindow(_:)` is called by `FrameProcessor` on
/// the camera frames queue. It spawns a `Task` to run the export asynchronously
/// so the camera pipeline is never blocked. Progress is published on the main
/// actor so SwiftUI bindings update smoothly.
@Observable
final class DrivingSession {

    private(set) var clips: [Clip] = []
    private(set) var isExporting = false
    /// Export progress in [0, 1]; only meaningful when `isExporting == true`.
    private(set) var exportProgress: Float = 0
    let startedAt = Date()

    private let exporter = ClipExporter()

    /// Called by `FrameProcessor` when a complete frame window (pre + post strike)
    /// is ready. Kicks off the export on a background task without blocking the
    /// camera pipeline.
    func handleFrameWindow(_ frames: [CMSampleBuffer]) {
        Task {
            await exportClip(frames: frames)
        }
    }

    /// Encodes the frames, appends the resulting clip, and gives haptic feedback.
    ///
    /// Runs on the main actor so all `@Observable` property mutations are safe
    /// to read from SwiftUI. The actual encoding work inside `ClipExporter` is
    /// async and runs off the main thread (the actor isolates the file I/O).
    @MainActor
    private func exportClip(frames: [CMSampleBuffer]) async {
        isExporting = true
        exportProgress = 0
        // Heavy impact gives the golfer tactile confirmation that the app caught
        // their swing before the clip is fully encoded.
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        defer { isExporting = false; exportProgress = 0 }
        do {
            let clip = try await exporter.export(frames: frames) { [weak self] progress in
                // Progress callback fires inside the actor (off main thread),
                // so we hop back to MainActor before updating @Observable state.
                Task { @MainActor [weak self] in self?.exportProgress = progress }
            }
            clips.append(clip)
            // Success notification when the file is fully written and the clip
            // is ready to review.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            // Non-fatal: the golfer can still review clips that exported successfully.
            print("⚠️ Clip export failed: \(error.localizedDescription)")
        }
    }

    var clipCount: Int { clips.count }

    /// Removes a clip from the in-memory session array (e.g. after the user
    /// deletes it from the grid). Does not touch the file system or SwiftData —
    /// callers are responsible for those operations.
    func removeClip(_ clip: Clip) {
        clips.removeAll { $0.id == clip.id }
    }

#if DEBUG
    /// Appends a pre-built clip directly — used by the simulator debug button
    /// and unit tests to populate the session without a live camera.
    func injectClipForDebug(_ clip: Clip) {
        clips.append(clip)
    }
#endif
}
