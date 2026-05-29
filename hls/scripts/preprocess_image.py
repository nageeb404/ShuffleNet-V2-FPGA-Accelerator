"""
preprocess_image.py -- Preprocess test images for HLS C simulation.

using integer data type as a reference."

Uses the same preprocessing and forward pass as verify_accuracy.py (the
confirmed-working script with 71% ImageNet accuracy). Resize short side to
256, center-crop 224x224, normalize, quantize to Q6.8.

For each image:
 1. Runs Python Q6.8 model (verify_accuracy.py pipeline) to get expected class
 2. Writes SM1 binary: 226x226x3 int16, channel-major, 1-px zero border
 -> loaded by HLS testbench when USE_SYNTHETIC_INPUT=0

Usage (from project root N:\\GP\\shufflenet_rtl):
 python hls/scripts/preprocess_image.py <image_path> [output.bin]
"""

import sys, os, copy, math, time
import numpy as np
from PIL import Image

# Add project root to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

# Import the confirmed-working pipeline from verify_accuracy.py
from scripts.verify_accuracy import (
 fold_all_bn, extract_q68_weights, forward_q68,
 preprocess_image as va_preprocess, load_imagenet_labels
)

def run_python_model(img_path, W, labels):
 """Run Q6.8 model using verify_accuracy.py pipeline. Returns class index."""
 t0 = time.time
 img = va_preprocess(img_path)
 scores = forward_q68(img, W)
 dt = time.time - t0
 cls = int(np.argmax(scores))
 lbl = labels[cls] if labels else str(cls)
 top5 = np.argsort(scores)[::-1][:5]
 print(f" Forward pass: {dt:.1f}s")
 print(f" Python Q6.8 Top-5:")
 for rank, idx in enumerate(top5):
 name = labels[idx] if labels else str(idx)
 print(f" #{rank+1} class {idx:4d} score={scores[idx]:7d} {name}")
 return cls

def preprocess_to_sm1_binary(img_path, out_path):
 """Preprocess image and write SM1-format binary (226x226x3 int16)."""
 pil_img = Image.open(img_path).convert("RGB")
 print(f" Image size: {pil_img.size[0]}x{pil_img.size[1]}")

 # Use the same preprocessing as verify_accuracy.py
 q_img = va_preprocess(img_path) # [3, 224, 224] int32

 # Wrap in 226x226 zero-padded SM1 layout (1-px border)
 sm1 = np.zeros((3, 226, 226), dtype=np.int16)
 sm1[:, 1:225, 1:225] = q_img.astype(np.int16)

 sm1.tofile(out_path)
 print(f" Binary: {out_path} ({os.path.getsize(out_path)} bytes)")

def main:
 if len(sys.argv) < 2:
 print(__doc__)
 sys.exit(1)

 img_path = sys.argv[1]
 if not os.path.exists(img_path):
 print(f"ERROR: {img_path} not found")
 sys.exit(1)

 out_path = sys.argv[2] if len(sys.argv) > 2 else \
 os.path.join(os.path.dirname(__file__), '..', 'tb', 'test_image.bin')
 out_path = os.path.abspath(out_path)

 print(f"\n=== HLS Image Preprocessor ===")
 print(f"Image : {img_path}")
 print(f"Output: {out_path}\n")

 # Load model once
 import torch
 from torchvision import models
 print("[1] Loading ShuffleNet V2 x1.0 ...")
 wts = models.ShuffleNet_V2_X1_0_Weights.DEFAULT
 m = models.shufflenet_v2_x1_0(weights=wts).eval
 mbn = copy.deepcopy(m)
 fold_all_bn(mbn); mbn.eval
 W = extract_q68_weights(mbn)
 labels = load_imagenet_labels
 print(f" Loaded. {len(W['blocks'])} shuffle blocks.\n")

 # Step 1: Python Q6.8 prediction
 print("[2] Running Python Q6.8 forward pass ...")
 expected = run_python_model(img_path, W, labels)

 # Step 2: Write SM1 binary
 print(f"\n[3] Writing SM1 binary ...")
 preprocess_to_sm1_binary(img_path, out_path)

 print(f"\n--- Result ---")
 lbl = labels[expected] if labels else str(expected)
 print(f" Python Q6.8 class: {expected} ({lbl})")
 print(f" Binary written: {out_path}")
 print(f" Set EXPECTED_CLASS={expected} in testbench or TCL cflags.")

if __name__ == "__main__":
 main
