import Foundation
import Observation

/// Represents one driving-range session and the clips captured during it.
@Observable
final class DrivingSession {

    private(set) var clips: [Clip] = []
    private(set) var isExporting = false
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
        defer { isExporting = false }
        do {
            let clip = try await exporter.export(frames: frames)
            clips.append(clip)
        } catch {
            // Non-fatal: log and continue. The golfer can still review
            // clips that were successfully exported.
            print("⚠️ Clip export failed: \(error.localizedDescription)")
        }
    }

    var clipCount: Int { clips.count }
}
