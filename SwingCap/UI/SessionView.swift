import SwiftUI

/// The main screen shown during an active driving-range session.
/// Phase 1: displays the live camera feed and buffer stats.
/// Phase 2: will show clip count and detection status overlay.
struct SessionView: View {

    @State private var camera = CameraSession()
    @State private var processor: FrameProcessor?
    @State private var setupError: CameraError?

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
            Spacer()
            statusPill
                .padding(.bottom, 48)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(camera.isRunning ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(camera.isRunning ? "Watching for impact…" : "Starting camera…")
                .font(.caption)
                .foregroundStyle(.white)

            if let proc = processor {
                Divider()
                    .frame(height: 12)
                    .background(.white.opacity(0.4))

                Text("\(proc.rollingBuffer.frameCount) frames buffered")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
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
        do {
            try camera.configure()
            camera.start()
        } catch let err as CameraError {
            setupError = err
        } catch {
            setupError = .deviceUnavailable
        }
    }
}

#Preview {
    SessionView()
}
