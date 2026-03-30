import SwiftUI

/// The main screen during an active driving-range session.
/// Shows the live camera feed with a HUD overlay.
struct SessionView: View {

    @Environment(SessionStore.self) private var sessionStore

    @State private var camera = CameraSession()
    @State private var processor: FrameProcessor?
    @State private var session = DrivingSession()
    @State private var setupError: CameraError?
    @State private var showClipFlash = false
    @State private var showClipReview = false
    @State private var showHistory = false
    /// The SwiftData record for the current active session, created on first launch.
    @State private var activeRecord: PersistedSession?

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
        .onChange(of: session.clips.count) { _, _ in persistLatestClip() }
    }

    // MARK: - Subviews

    private var cameraFeed: some View {
        CameraPreviewView(session: camera)
            .ignoresSafeArea()
    }

    private var hud: some View {
        VStack {
            // Top row: debug/history buttons (leading) + clip counter (trailing)
            HStack {
#if DEBUG
                debugInjectButton
                    .padding(.top, 16)
                    .padding(.leading, 16)
#endif
                historyButton
                    .padding(.top, 16)
                    .padding(.leading, 16)
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
        .sheet(isPresented: $showClipReview) {
            ClipGridView(session: session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showHistory) {
            SessionHistoryView()
                .environment(sessionStore)
        }
    }

    private var historyButton: some View {
        Button {
            showHistory = true
        } label: {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .opacity(sessionStore.pastSessions.isEmpty ? 0 : 1)
        .animation(.easeIn(duration: 0.2), value: sessionStore.pastSessions.count)
    }

    private var clipCounter: some View {
        Button {
            guard session.clipCount > 0 else { return }
            showClipReview = true
        } label: {
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
        .buttonStyle(.plain)
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
        // Create a persisted record for this session up front.
        activeRecord = sessionStore.beginSession(startedAt: session.startedAt)

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

    /// Called reactively whenever `session.clips` grows — persists the newest clip.
    private func persistLatestClip() {
        guard let record = activeRecord, let clip = session.clips.last else { return }
        sessionStore.addClip(clip, to: record)
    }

#if DEBUG
    /// Injects a placeholder clip so the review UI can be tested in the
    /// Simulator without a physical device or live camera session.
    private var debugInjectButton: some View {
        Button {
            let thumbnail = UIImage(systemName: "figure.golf")
            let clip = Clip(url: URL(fileURLWithPath: "/dev/null"),
                            thumbnail: thumbnail,
                            duration: 3.0)
            session.injectClipForDebug(clip)
            Task { @MainActor in await flashScreen() }
        } label: {
            Label("+ Clip", systemImage: "plus.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.8), in: Capsule())
        }
        .buttonStyle(.plain)
    }
#endif

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
