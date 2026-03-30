# ML Model — Training & Export

This guide covers how to get `GolfBallDetector.mlpackage` into the app.

---

## Quick start (base COCO weights)

If you just want to see the Core ML pipeline running without a custom model:

```bash
python3 scripts/export_model.py
```

This downloads `yolov8n.pt` (COCO-trained, ~6 MB) and exports it. The model
can detect round objects but won't be golf-ball-specific. Accuracy improves
significantly with fine-tuning (see below).

---

## Fine-tuning on golf ball footage

### 1. Collect data

Record 30–60 minutes of driving range footage from your phone's perspective
(tripod height, looking at the tee). Aim for a variety of:
- Ball positions (tee, mat, ground)
- Lighting conditions (morning, midday, overcast)
- Backgrounds (grass, mats, netting, sky)

About 500–1000 annotated frames is a good starting point.

### 2. Annotate

Use [Roboflow](https://roboflow.com) (free tier is fine) or [CVAT](https://cvat.ai):
- Draw bounding boxes around the golf ball in each frame
- Class name: **`golf_ball`** (must match `CoreMLBallDetector.targetClassName`)
- Export in **YOLOv8 format**

### 3. Train

```bash
pip install ultralytics

yolo train \
  model=yolov8n.pt \
  data=path/to/golf_ball.yaml \
  epochs=50 \
  imgsz=640 \
  batch=16 \
  name=swingcap_v1
```

Training takes ~20 minutes on an M-series Mac for 50 epochs on ~1000 images.

Expected results after fine-tuning:
- mAP@0.5 > 0.85 on validation set
- Inference < 10ms on iPhone 12+ (Neural Engine)

### 4. Export to Core ML

```bash
python3 scripts/export_model.py \
  --weights runs/detect/swingcap_v1/weights/best.pt \
  --imgsz 640
```

### 5. Rebuild

```bash
cd /path/to/SwingCap
xcodegen generate
```

Open Xcode, build, and run. The console will print:

```
SwingCap: upgraded to Core ML ball detector
```

---

## Tuning detection constants

After testing on real footage, open the in-app **Settings** screen to adjust:

| Setting | Default | Effect |
|---------|---------|--------|
| Motion threshold | 0.035 | Higher = less sensitive to motion (motion detector) |
| Cooldown | 3.0s | Minimum time between clips |
| Min ML confidence | 0.45 | Lower = more sensitive but more false positives |
| Departure frames | 4 | How many missed frames before declaring a strike |

Alternatively edit the constants directly in `CoreMLBallDetector.swift` and
`MotionThresholdDetector.swift` and rebuild.

---

## Troubleshooting

**Model not loading:**
- Confirm `GolfBallDetector.mlpackage` is in `SwingCap/Detection/Models/`
- Re-run `xcodegen generate` and rebuild
- Check the console for: `GolfBallDetector.mlpackage not found — using motion threshold`

**Too many false positives:**
- Increase `minBallConfidence` (try 0.55–0.65)
- Increase `departureFrameThreshold` (try 6–8)

**Missing real strikes:**
- Decrease `minBallConfidence` (try 0.35)
- Decrease `departureFrameThreshold` (try 2–3)
- Check the debug overlay (#if DEBUG build) to see live confidence scores

**Ball detected at wrong location:**
- Verify the class name in your training data matches `CoreMLBallDetector.targetClassName` (`"golf_ball"`)
