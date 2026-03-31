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
///
/// **Gesture rating flow**: `handleGestureEvent(_:)` is called (on the main
/// queue) when a thumbs gesture is confirmed. It applies the rating to the
/// most recently exported clip, replacing it in `clips` with an updated copy.
/// If the export hasn't finished yet (rare — gestures take ~2 s, export ~1 s)
/// the rating is queued in `pendingRating` and applied automatically when the
/// export completes. `SessionView` observes the `onRatingApplied` callback to
/// persist the updated clip to SwiftData.
@Observable
final class DrivingSession {

    private(set) var clips: [Clip] = []
    private(set) var isExporting = false
    /// Export progress in [0, 1]; only meaningful when `isExporting == true`.
    private(set) var exportProgress: Float = 0
    let startedAt = Date()

    /// Called on the main thread when a rating is applied to a clip (gesture
    /// or manual tap). `SessionView` uses this to persist the update.
    var onRatingApplied: ((Clip) -> Void)?

    private let exporter = ClipExporter()
    /// Queued gesture rating applied to the next exported clip if the gesture
    /// fires before the export task finishes.
    private var pendingRating: ShotRating?

    // MARK: - Frame window (strike captured)

    /// Called by `FrameProcessor` when a complete frame window (pre + post
    /// strike) is ready. Kicks off the export without blocking the pipeline.
    func handleFrameWindow(_ frames: [CMSampleBuffer]) {
        Task {
            await exportClip(frames: frames)
        }
    }

    // MARK: - Gesture rating

    /// Called by `SessionView` when `FrameProcessor.onGestureReady` fires.
    ///
    /// If the clip export has finished, the most recent clip is updated
    /// immediately. If not (export still in flight), the rating is saved in
    /// `pendingRating` and automatically applied once encoding completes.
    @MainActor
    func handleGestureEvent(_ rating: ShotRating) {
        if let last = clips.last {
            applyRating(rating, to: last)
        } else {
            // Export hasn't appended the clip yet — queue the rating.
            pendingRating = rating
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Updates a clip's rating in the in-memory array and notifies the
    /// `onRatingApplied` callback so the caller can persist the change.
    @MainActor
    func applyRating(_ rating: ShotRating?, to clip: Clip) {
        guard let idx = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let updated = clip.withRating(rating)
        clips[idx] = updated
        onRatingApplied?(updated)
    }

    // MARK: - Export

    @MainActor
    private func exportClip(frames: [CMSampleBuffer]) async {
        isExporting = true
        exportProgress = 0
        // Heavy impact gives the golfer tactile confirmation that the app caught
        // their swing before the clip is fully encoded.
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        defer { isExporting = false; exportProgress = 0 }
        do {
            var clip = try await exporter.export(frames: frames) { [weak self] progress in
                Task { @MainActor [weak self] in self?.exportProgress = progress }
            }
            // Apply any gesture rating that arrived while encoding was in flight.
            if let queued = pendingRating {
                pendingRating = nil
                clip = clip.withRating(queued)
            }
            clips.append(clip)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Notify observer (SessionView) so the rating can be persisted.
            if clip.rating != nil { onRatingApplied?(clip) }
        } catch {
            print("⚠️ Clip export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    var clipCount: Int { clips.count }

    /// Removes a clip from the in-memory session array.
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
