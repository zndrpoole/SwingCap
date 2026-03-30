# SwingCap — Todo

Two sections: tasks Claude can complete autonomously, and tasks that need you.

---

## ✅ Done

- [x] Camera session (AVFoundation, 60fps, 1280×720)
- [x] Rolling frame buffer (120-frame ring buffer, ~2s pre-strike)
- [x] Motion-threshold strike detector (placeholder, works today)
- [x] Post-strike capture (60 frames / ~1s after impact)
- [x] Clip export (H.264 MP4 via AVAssetWriter + thumbnail)
- [x] Clip review UI (thumbnail grid + full-screen player)
- [x] Playback controls (0.25×/0.5×/1× speed, scrubber, frame-step, loop)
- [x] Core ML detection pipeline (VNCoreMLRequest + ball tracking state machine)
- [x] Motion threshold fallback when model is absent
- [x] SwiftData session persistence (survives app restarts)
- [x] Session history screen (browse + delete past sessions)
- [x] Share to Photos (PHPhotoLibrary with permission request + toast)
- [x] Assets.xcassets (AppIcon placeholder + AccentColor)
- [x] ML model export script (`scripts/export_model.py`)
- [x] Unit tests (RollingFrameBuffer, BallStrikeDetector, ClipPlayerViewModel)
- [x] Simulator debug mode (#if DEBUG clip injection button)
- [x] **SwiftLint config** — `.swiftlint.yml` added with sensible rules
- [x] **Onboarding / permission screen** — `OnboardingView.swift`; shown on first launch, gates camera permission
- [x] **Detection confidence overlay** — `DebugOverlayView.swift`; `#if DEBUG` only; shows live motion score, detector type, buffer fill, clip count
- [x] **Clip deletion** — long-press context menu on grid cells; removes MP4 from disk
- [x] **Storage cleanup** — `ClipStorageManager.deleteOrphanedFiles` called on `SessionStore` init
- [x] **Haptic feedback** — heavy impact on strike detection, success notification on clip saved
- [x] **Detection sensitivity settings** — `SettingsView.swift`; sliders for all 4 detection constants, persisted in `UserDefaults`; gear button on HUD
- [x] **Clip notes field** — `notes: String` on `PersistedClip`; editable text field in player; auto-saved on dismiss
- [x] **Clip count badge on history button** — green capsule badge showing total clips across all past sessions
- [x] **GitHub Actions CI** — `.github/workflows/ci.yml`; builds + tests on every push using macOS runner + XcodeGen
- [x] **Makefile** — `make build`, `make test`, `make lint`, `make export-model`, `make clean`
- [x] **`ClipExporter` progress callback** — `onProgress: ((Float) -> Void)?` parameter; HUD shows real linear progress bar
- [x] **Session duration label** — live elapsed timer (M:SS) in the status pill
- [x] **Empty `Documents/SwingCap/Clips/` guard** — `ClipStorageManager` handles orphaned files; player receives graceful error if file missing
- [x] **Memory pressure test** — two unit tests: fill to capacity asserts count never exceeds limit; peak memory measurement asserts < 250 MB budget
- [x] **Notes UI in player** — `TextField` in `ClipPlayerView` edits/saves `PersistedClip.notes` via `SessionStore.updateNotes(_:for:)`
- [x] **Settings actually applied to detectors** — `MotionThresholdDetector` and `CoreMLBallDetector` now read `effectiveThreshold`/`effectiveCooldown`/`effectiveMinConfidence`/`effectiveDepartureThreshold` from `UserDefaults` at runtime
- [x] **CI xcpretty fix** — `gem install xcpretty` step added before build/test in `.github/workflows/ci.yml`
- [x] **Clip delete data integrity** — `ClipGridView.deleteClip` now calls `SessionStore.removeClip(_:)` to remove the `PersistedClip` SwiftData record alongside the MP4 file; static clip list updates so the grid refreshes immediately
- [x] **Background/foreground + interruption handling** — `CameraSession` subscribes to `UIApplication.willResignActiveNotification`, `didBecomeActiveNotification`, `AVCaptureSessionWasInterrupted`, and `AVCaptureSessionInterruptionEnded` to stop/restart automatically
- [x] **Low-storage guard** — `ClipExporter` checks available disk space before writing; throws `ExportError.insufficientStorage` when < 50 MB free

---

## 🤖 Claude can do — no input needed

### Documentation

- [x] **`README.md`** — project overview, setup, commands, architecture notes
- [x] **`scripts/README.md`** — dataset collection, annotation, training, export, and tuning guide
- [ ] **Inline doc comments** — public interfaces in `CameraSession`, `RollingFrameBuffer`, and `ClipExporter` are well-commented; audit the rest

---

## 👤 Needs you

### Before first build

- [ ] **Set Development Team** — open `SwingCap.xcodeproj` → Signing & Capabilities → set your Apple Developer Team ID (or set `DEVELOPMENT_TEAM` in `project.yml`)
- [ ] **Physical iPhone** — plug in a device; `AVCaptureSession` and Core ML on the Neural Engine do not run in the iOS Simulator
- [ ] **Run `xcodegen generate`** — required once after every `project.yml` change before opening in Xcode:
  ```bash
  brew install xcodegen   # first time only
  cd SwingCap && xcodegen generate
  open SwingCap.xcodeproj
  ```

### ML model (required for accurate detection)

- [ ] **Export base model** — run `python3 scripts/export_model.py` on your Mac (requires Python 3.9+); this gets the app using CoreML even with generic COCO weights
- [ ] **Collect training data** — record 30–60 minutes of driving range footage; annotate golf balls using [Roboflow](https://roboflow.com) or CVAT (bounding boxes, class: `golf_ball`)
- [ ] **Fine-tune the model** — `yolo train model=yolov8n.pt data=golf_ball.yaml epochs=50`; re-export with `scripts/export_model.py --weights runs/detect/train/weights/best.pt`
- [ ] **Tune detection constants** — after testing on real footage, adjust `CoreMLBallDetector.minBallConfidence`, `departureFrameThreshold`, and `MotionThresholdDetector.motionThreshold` to reduce false positives/negatives for your specific range setup

### Design

- [ ] **App icon** — design a 1024×1024 PNG (`AppIcon.appiconset/`); the current asset catalog has a placeholder with no image
- [ ] **Accent color** — currently set to `#33CC33` (green); adjust to match your brand in `AccentColor.colorset/Contents.json`

### Distribution

- [ ] **Privacy policy** — required for App Store; must cover camera usage and local storage (no data leaves the device)
- [ ] **App Store metadata** — name, subtitle, description, keywords, category (Sports)
- [ ] **Screenshots** — App Store requires screenshots for iPhone 6.9" and 6.5" sizes (can use the Simulator for UI shots, device for camera shots)
- [ ] **TestFlight beta** — archive in Xcode → distribute to TestFlight for real-device testing before App Store submission
- [ ] **App Store review** — submit for review; allow 1–3 days; camera-only apps sometimes require a brief explanation in the review notes

### Testing (requires device)

- [ ] **End-to-end test** — set phone on a tripod at the range, hit 10 balls, verify clips are saved and playable
- [ ] **False positive rate** — count how many clips are triggered by non-strike events (walking past, wind, birds); tune `motionThreshold` / `cooldownSeconds` accordingly
- [ ] **Memory profile** — run Instruments (Allocations + Leaks) during a 10-minute session to verify the rolling buffer stays within the ~50 MB target
- [ ] **60fps verification** — run Instruments (Time Profiler) to confirm the frame pipeline holds 60fps on your target device without dropping frames
