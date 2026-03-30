import AVFoundation
import SwiftUI

/// Shown on first launch before the camera session starts.
/// Explains the app, requests camera permission, then hands off to `SessionView`.
struct OnboardingView: View {

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var permissionStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isRequesting = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                icon
                    .padding(.bottom, 32)
                headline
                    .padding(.bottom, 40)
                featureList
                    .padding(.bottom, 56)
                Spacer()
                actionButton
                    .padding(.horizontal, 32)
                    .padding(.bottom, 52)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: permissionStatus) { _, status in
            if status == .authorized { completeOnboarding() }
        }
    }

    // MARK: - Subviews

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.15))
                .frame(width: 100, height: 100)
            Image(systemName: "figure.golf")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.green)
        }
    }

    private var headline: some View {
        VStack(spacing: 12) {
            Text("SwingCap")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("Set up your phone, swing away.\nYour clips save themselves.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 20) {
            FeatureRow(
                icon: "video.fill",
                color: .green,
                title: "Automatic capture",
                description: "Detects ball impact and saves a clip instantly — no tapping required."
            )
            FeatureRow(
                icon: "clock.arrow.2.circlepath",
                color: .blue,
                title: "2 seconds before impact",
                description: "A rolling buffer keeps the moment before your swing."
            )
            FeatureRow(
                icon: "slowmo",
                color: .orange,
                title: "Slow-motion review",
                description: "Play back at 0.25×, step frame-by-frame, scrub to any moment."
            )
            FeatureRow(
                icon: "internaldrive",
                color: .purple,
                title: "On-device, private",
                description: "Everything stays on your phone. Nothing is uploaded."
            )
        }
        .padding(.horizontal, 32)
    }

    private var actionButton: some View {
        Group {
            switch permissionStatus {
            case .authorized:
                Button(action: completeOnboarding) {
                    label(text: "Get Started", loading: false)
                }
                .buttonStyle(PrimaryButtonStyle())

            case .denied, .restricted:
                VStack(spacing: 12) {
                    Text("Camera access is required.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        label(text: "Open Settings", loading: false)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

            default: // .notDetermined
                Button(action: requestPermission) {
                    label(text: "Allow Camera Access", loading: isRequesting)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isRequesting)
            }
        }
    }

    private func label(text: String, loading: Bool) -> some View {
        HStack(spacing: 10) {
            if loading { ProgressView().tint(.black) }
            Text(text).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Actions

    private func requestPermission() {
        isRequesting = true
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                isRequesting = false
                permissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }

    private func completeOnboarding() {
        withAnimation { hasCompletedOnboarding = true }
    }
}

// MARK: - Supporting views

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineSpacing(2)
            }
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .background(Color.green.opacity(configuration.isPressed ? 0.8 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    OnboardingView()
}
