#if DEBUG
import SwiftUI

/// Floating diagnostic HUD shown only in DEBUG builds.
///
/// Displayed as a bottom-left overlay in `SessionView`. Gives real-time
/// visibility into the detection pipeline without requiring Instruments:
///
/// - **Detector**: which implementation is active (`MotionThresholdDetector`
///   or `CoreMLBallDetector`). Changes ~0.5s after app launch once the model loads.
/// - **Motion**: current luma-diff score. Shown in red when it exceeds
///   `MotionThresholdDetector.motionThreshold` (i.e. a strike would be emitted).
/// - **Buffer**: how many frames are currently in the rolling buffer. Should
///   stay near 120 while idle; drops to ~0 immediately after a strike.
/// - **Clips**: total clips saved in the current session.
/// - **Exporting**: appears (in yellow) only while `AVAssetWriter` is active.
struct DebugOverlayView: View {

    let motionScore: Float
    let detectorType: String
    let bufferedFrames: Int
    let isExporting: Bool
    let clipCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Detector", detectorType)
            row("Motion", String(format: "%.4f", motionScore),
                color: motionScore > MotionThresholdDetector.motionThreshold ? .red : .green)
            row("Buffer", "\(bufferedFrames) frames")
            row("Clips", "\(clipCount)")
            if isExporting { row("Exporting", "…", color: .yellow) }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(10)
        .background(.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ label: String, _ value: String, color: Color = .white) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 70, alignment: .leading)
            Text(value)
                .foregroundStyle(color)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        DebugOverlayView(
            motionScore: 0.041,
            detectorType: "MotionThresholdDetector",
            bufferedFrames: 87,
            isExporting: false,
            clipCount: 3
        )
    }
}
#endif
