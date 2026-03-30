import SwiftUI

/// The main screen during an active driving-range session.
/// Shows the live camera feed with a HUD overlay.
struct SessionView: View {

    @State private var camera = CameraSession()
    @State private var processor: FrameProcessor?
    @State private var session = DrivingSession()
    @State private var setupError: CameraError?
    @State private var showClipFlash = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let error = setupError {
                errorView(error)
            } else {
                cameraFeed
                hud
            }
        }
        .task { await startCamera() }
        .onDisappear { camera.stop() }
    }

    // MARK: - Subviews

    private var cameraFeed: some View {
        CameraPreviewView(session: camera)
            .ignoresSafeArea()
    }

    private var hud: some View {
        VStack {
            // Top-right: clip counter
            HStack {
                Spacer()
                clipCounter
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }

            Spacer()

            // Bottom-center: status pill
            statusPill
                .padding(.bottom, 48)
        }
        // Brief white flash when a clip is saved
        .overlay {
            if showClipFlash {
                Color.white.opacity(0.3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showClipFlash)
    }

    private var clipCounter: some View {
        HStack(spacing: 6) {
            Image(systemName: "video.fill")
                .font(.caption)
            Text("\(session.clipCount)")
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .opacity(session.clipCount > 0 ? 1 : 0)
        .animation(.easeIn(duration: 0.2), value: session.clipCount)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            // Live indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.white)

            if session.isExporting {
                Divider().frame(height: 12).background(.white.opacity(0.4))
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var statusColor: Color {
        if !camera.isRunning { return .orange }
        if session.isExporting { return .yellow }
        return .green
    }

    private var statusLabel: String {
        if !camera.isRunning { return "Starting camera…" }
        if session.isExporting { return "Saving clip…" }
        return "Watching for impact…"
    }

    private func errorView(_ error: CameraError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text(error.errorDescription ?? "Camera unavailable")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal)
        }
    }

    // MARK: - Camera startup

    @MainActor
    private func startCamera() async {
        let proc = FrameProcessor()
        self.processor = proc
        camera.frameProcessor = proc

        proc.onFrameWindowReady = { [session] frames in
            session.handleFrameWindow(frames)
            Task { @MainActor in
                await flashScreen()
            }
        }

        do {
            try camera.configure()
            camera.start()
        } catch let err as CameraError {
            setupError = err
        } catch {
            setupError = .deviceUnavailable
        }
    }

    @MainActor
    private func flashScreen() async {
        showClipFlash = true
        try? await Task.sleep(for: .milliseconds(200))
        showClipFlash = false
    }
}

#Preview {
    SessionView()
}
