import Foundation
import Observation
import UIKit

/// Represents one driving-range session and the clips captured during it.
@Observable
final class DrivingSession {

    private(set) var clips: [Clip] = []
    private(set) var isExporting = false
    /// Export progress in [0, 1]; only meaningful when `isExporting == true`.
    private(set) var exportProgress: Float = 0
    let startedAt = Date()

    private let exporter = ClipExporter()

    /// Called by `FrameProcessor` when a complete frame window is ready.
    /// Runs the export on a background task and appends the resulting clip.
    func handleFrameWindow(_ frames: [CMSampleBuffer]) {
        Task {
            await exportClip(frames: frames)
        }
    }

    @MainActor
    private func exportClip(frames: [CMSampleBuffer]) async {
        isExporting = true
        exportProgress = 0
        // Heavy impact on detection — gives tactile confirmation the strike was caught.
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        defer { isExporting = false; exportProgress = 0 }
        do {
            let clip = try await exporter.export(frames: frames) { [weak self] progress in
                Task { @MainActor [weak self] in self?.exportProgress = progress }
            }
            clips.append(clip)
            // Soft notification when the clip file is ready.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            // Non-fatal: log and continue. The golfer can still review
            // clips that were successfully exported.
            print("⚠️ Clip export failed: \(error.localizedDescription)")
        }
    }

    var clipCount: Int { clips.count }

    /// Removes a clip from the in-memory session (e.g. after user deletion).
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
