import SwiftUI

/// Lets the user tune detection sensitivity and view storage stats.
/// Presented as a sheet from `SessionView`.
///
/// ## UserDefaults contract
///
/// The four `@AppStorage` keys written here are read at runtime by the
/// detector classes via their `effective*` computed properties:
///
/// | Key                      | Read by                                   |
/// |--------------------------|-------------------------------------------|
/// | `"motionThreshold"`      | `MotionThresholdDetector.effectiveThreshold`  |
/// | `"cooldownSeconds"`      | `MotionThresholdDetector.effectiveCooldown`   |
/// | `"mlMinConfidence"`      | `CoreMLBallDetector.effectiveMinConfidence`   |
/// | `"departureFrameThreshold"` | `CoreMLBallDetector.effectiveDepartureThreshold` |
///
/// Changes take effect on the very next camera frame — no session restart needed.
/// Defaults (shown in the slider hints) come from each detector's static `let` constants.
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    // MARK: - Detection settings (persisted in UserDefaults)

    @AppStorage("motionThreshold")
    private var motionThreshold: Double = Double(MotionThresholdDetector.motionThreshold)

    @AppStorage("cooldownSeconds")
    private var cooldownSeconds: Double = MotionThresholdDetector.cooldownSeconds

    @AppStorage("mlMinConfidence")
    private var mlMinConfidence: Double = Double(CoreMLBallDetector.minBallConfidence)

    @AppStorage("departureFrameThreshold")
    private var departureFrameThreshold: Double = Double(CoreMLBallDetector.departureFrameThreshold)

    // MARK: - Storage

    @State private var storageSize = ClipStorageManager.formattedStorageSize()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    motionSection
                    mlSection
                    storageSection
                    resetSection
                }
                .scrollContentBackground(.hidden)
                .foregroundStyle(.white)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var motionSection: some View {
        Section {
            SliderRow(
                label: "Motion threshold",
                value: $motionThreshold,
                range: 0.01...0.15,
                format: "%.3f",
                hint: "Higher = less sensitive. Default: \(String(format: "%.3f", MotionThresholdDetector.motionThreshold))"
            )
            SliderRow(
                label: "Cooldown (s)",
                value: $cooldownSeconds,
                range: 1...10,
                format: "%.1f",
                hint: "Minimum seconds between clips. Default: \(String(format: "%.1f", MotionThresholdDetector.cooldownSeconds))"
            )
        } header: {
            Text("Motion detector")
        }
    }

    private var mlSection: some View {
        Section {
            SliderRow(
                label: "Min confidence",
                value: $mlMinConfidence,
                range: 0.1...0.9,
                format: "%.2f",
                hint: "YOLO confidence cutoff. Default: \(String(format: "%.2f", CoreMLBallDetector.minBallConfidence))"
            )
            SliderRow(
                label: "Departure frames",
                value: $departureFrameThreshold,
                range: 1...10,
                format: "%.0f",
                hint: "Missed frames before strike is declared. Default: \(CoreMLBallDetector.departureFrameThreshold)"
            )
        } header: {
            Text("Core ML detector")
        } footer: {
            Text("Only active when GolfBallDetector.mlpackage is bundled.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var storageSection: some View {
        Section {
            HStack {
                Text("Clips storage")
                Spacer()
                Text(storageSize)
                    .foregroundStyle(.white.opacity(0.6))
            }
        } header: {
            Text("Storage")
        }
        .onAppear { storageSize = ClipStorageManager.formattedStorageSize() }
    }

    private var resetSection: some View {
        Section {
            Button("Reset to defaults", role: .destructive) {
                motionThreshold = Double(MotionThresholdDetector.motionThreshold)
                cooldownSeconds = MotionThresholdDetector.cooldownSeconds
                mlMinConfidence = Double(CoreMLBallDetector.minBallConfidence)
                departureFrameThreshold = Double(CoreMLBallDetector.departureFrameThreshold)
            }
            .foregroundStyle(.red)
        }
    }
}

// MARK: - Slider row

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: format, value))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
                .tint(.green)
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SettingsView()
}
