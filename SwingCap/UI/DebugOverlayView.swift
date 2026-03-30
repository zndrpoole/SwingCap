#if DEBUG
import SwiftUI

/// Floating HUD shown in DEBUG builds only.
/// Displays live detection confidence, frame count, and export state.
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
