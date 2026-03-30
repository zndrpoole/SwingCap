# SwingCap

An iOS app that automatically captures your golf swings at the driving range.

Set up your phone, hit balls. SwingCap detects each impact using on-device machine learning and saves a clip of **2 seconds before + 1 second after** each strike for review when you're done.

---

## How it works

```
Camera (60fps)
  └─ Rolling buffer keeps last ~2 seconds of frames
  └─ Strike detector watches every frame
        └─ Impact detected → capture 1 more second
              └─ Export ~180 frames as H.264 MP4
                    └─ Clip appears in your session gallery
```

Detection runs entirely on-device. Nothing is uploaded or stored in the cloud.

---

## Requirements

| Requirement | Details |
|-------------|---------|
| Device | iPhone with back camera (physical device required — no Simulator support for live camera) |
| iOS | 17.0+ |
| Xcode | 15+ |
| Python | 3.9+ (for ML model export only) |

---

## Setup

### 1. Generate the Xcode project

```bash
# Install XcodeGen (first time only)
brew install xcodegen

# Clone and generate
git clone <repo-url> SwingCap
cd SwingCap
xcodegen generate
open SwingCap.xcodeproj
```

### 2. Set your Development Team

In Xcode → select the `SwingCap` target → **Signing & Capabilities** → set your Apple Developer Team.

Or edit `project.yml`:
```yaml
DEVELOPMENT_TEAM: "YOUR_TEAM_ID"
```

### 3. Build & run

Connect your iPhone and press **Cmd+R** in Xcode.

---

## Common commands

```bash
make build          # Build for Simulator (no signing required)
make test           # Run unit tests in Simulator
make lint           # Run SwiftLint (brew install swiftlint)
make export-model   # Export the Core ML golf ball model
make help           # Show all targets
```

---

## ML Model

The app ships with a motion-threshold detector that works out of the box. For more accurate ball-specific detection, bundle a trained Core ML model:

```bash
python3 scripts/export_model.py
```

This downloads YOLOv8-nano, exports it to `GolfBallDetector.mlpackage`, and places it in `SwingCap/Detection/Models/`. See [`scripts/README.md`](scripts/README.md) for fine-tuning instructions.

The app automatically upgrades from motion detection to Core ML when the model is present — no code changes needed.

---

## Project structure

```
SwingCap/
├── App/               Entry point, onboarding gate
├── Camera/            AVCaptureSession, rolling frame buffer, frame dispatch
├── Detection/         Strike detection (motion threshold + Core ML)
├── Clipping/          MP4 export, clip model, storage manager
├── Session/           DrivingSession, SessionStore (SwiftData persistence)
└── UI/                All SwiftUI views
SwingCapTests/
├── Camera/            RollingFrameBuffer tests
├── Detection/         BallStrikeDetector tests
└── UI/                ClipPlayerViewModel tests
scripts/
└── export_model.py    YOLOv8 → Core ML export pipeline
```

---

## Testing

Unit tests run in the iOS Simulator:

```bash
make test
```

For end-to-end testing you need a physical device:
1. Mount your phone on a tripod at a driving range (or a practice mat)
2. Build and run
3. Hit 10–20 balls
4. Review clips in the gallery

See `TODO.md` for what's left to do before App Store submission.

---

## Architecture notes

- **No third-party dependencies** — pure Apple frameworks
- **Swift concurrency throughout** — camera/detection on serial `DispatchQueue`, export on `actor`, UI on `@MainActor`
- **`@Observable`** for reactive UI — no Combine, no `@Published`
- **SwiftData** for persistence — sessions and clips survive reinstalls (MP4 files stay in `Documents/SwingCap/Clips/`)
- Detection constants (`motionThreshold`, `cooldownSeconds`, etc.) are named constants tunable via the in-app Settings screen
