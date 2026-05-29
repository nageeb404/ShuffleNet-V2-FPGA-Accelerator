"""
gen_test_image.py -- Convert a JPEG/PNG to the raw binary format
expected by shufflenet_test.c

Output format: 224*224*3 bytes, R-plane then G-plane then B-plane (planar),
pixel values 0..255, matching the photo_mem layout.

USAGE:
    python sw/gen_test_image.py --image /path/to/image.jpg --out image.bin
    python sw/gen_test_image.py --image /path/to/image.jpg  # prints predicted Q6.8 class too
"""
import argparse
import sys
import os
import numpy as np

PROJ_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJ_ROOT)

try:
    from PIL import Image
except ImportError:
    print("ERROR: pip install pillow"); sys.exit(1)

def preprocess(path, resize=256, crop=224):
    img = Image.open(path).convert("RGB")
    w, h = img.size
    if w <= h:
        new_w, new_h = resize, int(resize * h / w)
    else:
        new_w, new_h = int(resize * w / h), resize
    img = img.resize((new_w, new_h), Image.BILINEAR)
    left = (img.width  - crop) // 2
    top  = (img.height - crop) // 2
    img  = img.crop((left, top, left + crop, top + crop))
    return np.array(img, dtype=np.uint8)  # [224, 224, 3] HWC uint8

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--image", required=True)
    p.add_argument("--out",   default="image.bin")
    args = p.parse_args()

    arr = preprocess(args.image)   # [224, 224, 3] uint8
    # Convert to planar: R-plane, G-plane, B-plane (each 224*224 = 50176 bytes)
    r = arr[:, :, 0].flatten()
    g = arr[:, :, 1].flatten()
    b = arr[:, :, 2].flatten()
    planar = np.concatenate([r, g, b]).astype(np.uint8)

    with open(args.out, "wb") as f:
        f.write(planar.tobytes())
    print(f"Written: {args.out}  ({len(planar)} bytes)")
    print(f"  Shape: 224x224x3 planar (R, G, B planes)")

if __name__ == "__main__":
    main()
