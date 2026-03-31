import SwiftUI

/// The main screen during an active driving-range session.
/// Shows the live camera feed with a transparent HUD overlay.
///
/// ## Startup sequence
///
/// 1. `.task { await startCamera() }` fires when the view appears.
/// 2. `startCamera()` creates a `PersistedSession` record immediately via
///    `sessionStore.beginSession()` so clips can be appended incrementally.
/// 3. A `FrameProcessor` is created and wired into `CameraSession` as its
///    frame delegate. The processor's `onFrameWindowReady` closure calls
///    `session.handleFrameWindow(_:)` which spawns the encoding task.
/// 4. `camera.configure()` sets up the AVCaptureSession; `camera.start()`
///    begins the frame stream.
///
/// ## Persistence
///
/// `session.clips` is an `@Observable` array. SwiftUI re-evaluates the body
/// when its count changes. The `.onChange(of: session.clips.count)` modifier
/// calls `persistLatestClip()` to write each newly exported clip to SwiftData
/// exactly once.
///
/// ## HUD elements
///
/// - **History button** (top-left): shows a green badge with the total clip
///   count across all past sessions. Hidden when there are no past sessions.
/// - **Settings button** (top-left): opens `SettingsView` as a sheet.
/// - **Clip counter** (top-right): tappable pill showing the current session's
///   clip count; opens `ClipGridView` as a sheet for in-session review.
/// - **Status pill** (bottom-center): shows camera state, export progress, and
///   a live M:SS elapsed timer.
/// - **White flash overlay**: briefly shown (200ms) each time a clip is saved
///   to give tactile visual feedback.
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
    @State private var showSettings = false
    @State private var sessionElapsed: TimeInterval = 0
    /// `true` while `FrameProcessor` is in its `.awaitingGesture` state;
    /// drives the "Rate your shot" status pill variant.
    @State private var isAwaitingGesture = false
    /// Fires every second on the main run loop to update the elapsed timer label.
    private let sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
        // Each time a new clip is appended, persist it to SwiftData.
        .onChange(of: session.clips.count) { _, _ in persistLatestClip() }
        .onReceive(sessionTimer) { _ in
            guard camera.isRunning else { return }
            sessionElapsed = Date().timeIntervalSince(session.startedAt)
#if DEBUG
            isAwaitingGesture = processor?.isAwaitingGesture ?? false
#endif
        }
    }

    // MARK: - Subviews

    private var cameraFeed: some View {
        CameraPreviewView(session: camera)
            .ignoresSafeArea()
    }

    private var hud: some View {
        VStack {
            // Top row: history/settings (leading) + clip counter (trailing)
            HStack {
#if DEBUG
                debugInjectButton
                    .padding(.top, 16)
                    .padding(.leading, 16)
#endif
                historyButton
                    .padding(.top, 16)
                    .padding(.leading, 16)
                settingsButton
                    .padding(.top, 16)
                    .padding(.leading, 8)
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
#if DEBUG
        // Debug overlay shows live detection confidence, buffer fill, and export state.
        .overlay(alignment: .bottomLeading) {
            if let proc = processor {
                DebugOverlayView(
                    motionScore: proc.detector.lastScore,
                    detectorType: proc.detector.detectorTypeName,
                    bufferedFrames: proc.rollingBuffer.frameCount,
                    isExporting: session.isExporting,
                    clipCount: session.clipCount
                )
                .padding(.leading, 16)
                .padding(.bottom, 120)
            }
        }
#endif
        .sheet(isPresented: $showClipReview) {
            ClipGridView(session: session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showHistory) {
            SessionHistoryView()
                .environment(sessionStore)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    /// History button: visible only when past sessions exist, shows a green
    /// badge with the total clip count capped at 99.
    private var historyButton: some View {
        let totalClips = sessionStore.pastSessions.reduce(0) { $0 + $1.clipCount }
        return Button {
            showHistory = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())

                if totalClips > 0 {
                    Text("\(min(totalClips, 99))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.green, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(sessionStore.pastSessions.isEmpty ? 0 : 1)
        .animation(.easeIn(duration: 0.2), value: sessionStore.pastSessions.count)
    }

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// Tappable clip counter pill — tapping opens the in-session clip review grid.
    /// Hidden (opacity 0) when no clips have been saved yet.
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
            // Coloured dot: orange = camera not ready, yellow = exporting, green = watching
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.white)

            if session.isExporting {
                Divider().frame(height: 12).background(.white.opacity(0.4))
                ProgressView(value: session.exportProgress)
                    .progressViewStyle(.linear)
                    .tint(.green)
                    .frame(width: 48)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var statusColor: Color {
        if !camera.isRunning { return .orange }
        if session.isExporting { return .yellow }
        if isAwaitingGesture { return .blue }
        return .green
    }

    private var statusLabel: String {
        if !camera.isRunning { return "Starting camera…" }
        if session.isExporting { return "Saving clip…" }
        if isAwaitingGesture { return "Rate your shot 👍 👎" }
        return "Watching for impact…  \(formatElapsed(sessionElapsed))"
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
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

    /// Wires the full pipeline and starts the camera session.
    ///
    /// Order matters:
    /// 1. `sessionStore.beginSession()` — create the SwiftData record first so
    ///    `persistLatestClip()` always has a valid `activeRecord` to append to.
    /// 2. Create and wire `FrameProcessor` — its `onFrameWindowReady` must be
    ///    set before the session starts so no frames are missed.
    /// 3. `camera.configure()` + `camera.start()` — last, to ensure all
    ///    consumers are ready before frames begin arriving.
    @MainActor
    private func startCamera() async {
        activeRecord = sessionStore.beginSession(startedAt: session.startedAt)

        let proc = FrameProcessor()
        self.processor = proc
        camera.frameProcessor = proc

        proc.onFrameWindowReady = { [session] frames in
            session.handleFrameWindow(frames)
            Task { @MainActor in
                await flashScreen()
                // The processor transitions to .awaitingGesture immediately
                // after firing this callback — reflect that in the status pill.
                self.isAwaitingGesture = true
            }
        }

        // Gesture events fire on the main queue (dispatched by HandGestureDetector).
        // Route the rating to DrivingSession; DrivingSession's onRatingApplied
        // callback then persists it to SwiftData.
        proc.onGestureReady = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAwaitingGesture = false
                self.session.handleGestureEvent(event.rating)
            }
        }

        // Wire the rating persistence callback.
        session.onRatingApplied = { [weak self] updatedClip in
            self?.sessionStore.updateRating(updatedClip.rating, for: updatedClip)
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

    /// Called reactively whenever `session.clips` grows — persists the newest
    /// (last) clip to SwiftData via `sessionStore.addClip(_:to:)`.
    ///
    /// Using `session.clips.last` rather than a specific index is safe here
    /// because clips are only ever appended, never reordered.
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

    /// Shows a white flash overlay for 200ms — used as visual confirmation
    /// that a clip was just captured and saved.
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
