# SwingCap

## Project Overview

SwingCap is a native iOS app for golfers at the driving range. It runs a continuous camera session, uses on-device ML to detect the moment a golf ball is struck, and automatically saves a clip of approximately **2 seconds before and 1 second after impact** for review after the session.

The golfer simply sets up their phone, hits balls, and reviews their swings at the end — no manual recording required.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 5.9+ |
| UI | SwiftUI |
| Camera / video | AVFoundation (`AVCaptureSession`, `CMSampleBuffer`) |
| ML inference | Core ML + Apple Vision framework |
| Ball detection model | YOLOv8-nano (or similar) exported to `.mlpackage` |
| Persistence | FileManager + SwiftData (or Core Data) |
| Minimum deployment | iOS 17+ |

## Architecture

```
SwingCap/
├── App/
│   ├── SwingCapApp.swift          # @main entry point
│   └── ContentView.swift          # Root SwiftUI view
├── Camera/
│   ├── CameraSession.swift        # AVCaptureSession setup & lifecycle
│   ├── RollingFrameBuffer.swift   # Circular CMSampleBuffer ring buffer (~2s)
│   └── FrameProcessor.swift       # Dispatches frames to detector
├── Detection/
│   ├── BallStrikeDetector.swift   # Core ML + Vision inference pipeline
│   ├── StrikeEvent.swift          # Model: timestamp + confidence
│   └── Models/
│       └── GolfBallDetector.mlpackage
├── Clipping/
│   ├── ClipExporter.swift         # Assembles frames into MP4 via AVAssetWriter
│   └── Clip.swift                 # Model: file URL, timestamp, thumbnail
├── Session/
│   ├── DrivingSession.swift       # Manages a range session & its clips
│   └── SessionStore.swift         # Persists sessions with SwiftData
└── UI/
    ├── CameraPreviewView.swift    # Live viewfinder (AVCaptureVideoPreviewLayer)
    ├── SessionView.swift          # Active session screen
    ├── ClipGridView.swift         # Post-session clip gallery
    └── ClipPlayerView.swift       # Full-screen playback with scrubbing
```

## Core Data Flow

```
Camera frames (60fps)
    │
    ├──► RollingFrameBuffer   ← keeps last ~120 frames (~2s at 60fps)
    │
    └──► BallStrikeDetector   ← Vision + CoreML, runs on every frame
              │
              └── Strike detected?
                      │
                      Yes → freeze buffer snapshot + record 60 more frames (~1s)
                              │
                              └──► ClipExporter → saves ~180 frames as MP4
                                        │
                                        └──► SessionStore appends Clip
```

## Detection Strategy

Impact detection uses a two-stage approach:

1. **Ball tracking (pre-strike):** Vision's `VNDetectRectanglesRequest` or a custom `GolfBallDetector` Core ML model locates the stationary ball on the tee.
2. **Departure detection:** When the ball's bounding box disappears or velocity spikes beyond a threshold in consecutive frames, a `StrikeEvent` is emitted.
3. **Confidence gating:** Only events above a confidence threshold trigger clip capture to avoid false positives from other motion in the scene.

## Development Commands

```bash
# Open project
open SwingCap.xcodeproj

# Build (command line)
xcodebuild -scheme SwingCap -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run tests
xcodebuild test -scheme SwingCap -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Lint (if SwiftLint is added)
swiftlint lint
```

## Key Conventions

- **Actors for concurrency:** Camera and detection pipelines run on Swift `actor` types to avoid data races.
- **No third-party dependencies** unless strictly necessary — prefer Apple frameworks.
- **Frame buffer uses `CMSampleBuffer` retain/copy** — be careful with memory; always call `CMSampleBufferInvalidate` on evicted frames.
- **ClipExporter writes off main thread** using `AVAssetWriter` with `DispatchQueue`.
- **SwiftUI views are thin** — all business logic lives in `@Observable` view models or actors, not in views.
- **Testing:** Unit test the detection pipeline with pre-recorded frame sequences; UI tests are not required initially.

## Rolling Buffer Notes

- Target: **60 fps** capture for smooth slow-motion review.
- Buffer capacity: **~180 frames** (3 seconds total: 2s pre + 1s post).
- `CMSampleBuffer` objects must be explicitly retained (`CMSampleBufferCreateCopy`) when stored in the ring buffer.
- Memory budget: at 1080p/60fps a raw frame is ~6 MB; use `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` and keep the buffer compressed or limit to 720p during live capture.

## ML Model

- Export a YOLOv8-nano model trained on golf ball images to Core ML (`.mlpackage`).
- Input: `CVPixelBuffer` (640×640 or 416×416, RGB).
- Output: bounding boxes + confidence scores.
- Run inference via `VNCoreMLRequest` inside `BallStrikeDetector`.
- Target: inference under **10ms per frame** on an iPhone 12 or newer (Neural Engine).

## Notes for Claude

- The rolling buffer is the most memory-sensitive part of the app — always review memory implications when modifying `RollingFrameBuffer`.
- Detection sensitivity (confidence threshold, minimum ball size) should be tunable constants, not hardcoded magic numbers.
- The app requires camera and photo library permissions; keep `Info.plist` usage descriptions accurate.
- When adding UI, default to SwiftUI; use `UIViewRepresentable` only for `AVCaptureVideoPreviewLayer`.
- Clips are saved to the app's Documents directory, not the Photos library (unless the user explicitly exports).
