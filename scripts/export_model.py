#!/usr/bin/env python3
"""
export_model.py — Export a YOLOv8-nano Core ML model for SwingCap.

Usage:
    python3 scripts/export_model.py [--weights yolov8n.pt] [--imgsz 640]

The script:
  1. Installs ultralytics + coremltools if not present.
  2. Loads the specified weights (downloads from ultralytics if missing).
  3. Exports to Core ML with NMS post-processing baked in so that
     Vision produces VNRecognizedObjectObservation results directly.
  4. Renames the output to GolfBallDetector.mlpackage and moves it to
     SwingCap/Detection/Models/ next to this script's repo root.

Requirements:
    Python 3.9+  |  pip  |  ~500 MB disk for weights + model

A fine-tuned golf-ball model will outperform the default COCO weights.
See TRAINING.md (TODO) for dataset and fine-tuning instructions.
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = REPO_ROOT / "SwingCap" / "Detection" / "Models"
OUTPUT_NAME = "GolfBallDetector"

REQUIRED_PACKAGES = ["ultralytics>=8.0", "coremltools>=7.0"]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def ensure_packages() -> None:
    """Install required packages if not already available."""
    for pkg in REQUIRED_PACKAGES:
        try:
            name = pkg.split(">=")[0]
            __import__(name)
        except ImportError:
            print(f"Installing {pkg} …")
            subprocess.check_call([sys.executable, "-m", "pip", "install", pkg])


def export(weights: str, imgsz: int) -> Path:
    """Run the YOLO CoreML export and return the path to the .mlpackage."""
    from ultralytics import YOLO  # imported after ensure_packages()

    print(f"\nLoading weights: {weights}")
    model = YOLO(weights)

    print(f"Exporting to Core ML (imgsz={imgsz}, nms=True) …")
    export_path = model.export(
        format="coreml",
        imgsz=imgsz,
        nms=True,          # bakes NMS in so Vision returns VNRecognizedObjectObservation
        half=False,        # FP32 — more compatible across devices
    )

    mlpackage = Path(export_path)
    if not mlpackage.exists():
        # ultralytics sometimes returns the parent directory
        candidates = list(Path(".").glob("*.mlpackage"))
        if not candidates:
            raise FileNotFoundError(f"Could not locate exported .mlpackage near {export_path}")
        mlpackage = candidates[0]

    return mlpackage


def install(mlpackage: Path) -> Path:
    """Move the .mlpackage to SwingCap/Detection/Models/ with the correct name."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    dest = OUTPUT_DIR / f"{OUTPUT_NAME}.mlpackage"

    if dest.exists():
        print(f"Removing existing model at {dest}")
        shutil.rmtree(dest)

    shutil.move(str(mlpackage), str(dest))
    print(f"\nModel installed → {dest.relative_to(REPO_ROOT)}")
    return dest


def print_next_steps(dest: Path) -> None:
    rel = dest.relative_to(REPO_ROOT)
    print(f"""
Next steps
──────────
1. Regenerate the Xcode project so XcodeGen picks up the new bundle resource:
       cd {REPO_ROOT} && xcodegen generate

2. Open SwingCap.xcodeproj in Xcode and confirm that
   {rel} appears under the SwingCap target → Resources.

3. Build & run on device. The console will print:
       SwingCap: upgraded to Core ML ball detector
   once the model loads (~200 ms after launch).

4. If detection accuracy is poor with the base COCO weights, fine-tune
   on golf-ball footage. See scripts/README_training.md (TODO).
""")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Export YOLOv8 to Core ML for SwingCap")
    parser.add_argument(
        "--weights",
        default="yolov8n.pt",
        help="YOLOv8 weights file or model name (default: yolov8n.pt)",
    )
    parser.add_argument(
        "--imgsz",
        type=int,
        default=640,
        help="Square input size for the model (default: 640)",
    )
    args = parser.parse_args()

    print("SwingCap — Core ML model export")
    print("=" * 40)

    ensure_packages()

    mlpackage = export(args.weights, args.imgsz)
    dest = install(mlpackage)
    print_next_steps(dest)


if __name__ == "__main__":
    main()
