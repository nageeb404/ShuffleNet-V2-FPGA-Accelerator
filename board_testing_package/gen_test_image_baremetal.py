#!/usr/bin/env python3
"""
Preprocess a photo for the ShuffleNet V2 bare-metal board test.

Outputs:
  image.bin  -- 150,528 raw bytes (planar R-G-B), loaded to DDR via XSCT dow -data
  image.coe  -- 37,632 hex words (4 bytes packed per word), loaded via XSCT mwr loop

Usage:
  python gen_test_image_baremetal.py --image photo.jpg --out image

Requires:
  pip install pillow numpy
"""

import argparse
import struct
from pathlib import Path

import numpy as np
from PIL import Image


def preprocess(path: str) -> np.ndarray:
    img = Image.open(path).convert("RGB")

    # Resize shortest side to 256, keep aspect ratio
    w, h = img.size
    if w < h:
        new_w, new_h = 256, int(h * 256 / w)
    else:
        new_w, new_h = int(w * 256 / h), 256
    img = img.resize((new_w, new_h), Image.BILINEAR)

    # Center crop to 224x224
    left = (new_w - 224) // 2
    top  = (new_h - 224) // 2
    img  = img.crop((left, top, left + 224, top + 224))

    return np.array(img, dtype=np.uint8)   # shape (224, 224, 3)


def write_bin(path: Path, arr: np.ndarray) -> None:
    r = arr[:, :, 0].flatten()
    g = arr[:, :, 1].flatten()
    b = arr[:, :, 2].flatten()
    planar = np.concatenate([r, g, b])
    path.write_bytes(planar.tobytes())


def write_coe(path: Path, arr: np.ndarray) -> None:
    r = arr[:, :, 0].flatten()
    g = arr[:, :, 1].flatten()
    b = arr[:, :, 2].flatten()
    planar = np.concatenate([r, g, b])          # 150,528 bytes

    # Pad to multiple of 4 (already is: 150528 / 4 = 37632 exactly)
    assert len(planar) % 4 == 0

    words = []
    for i in range(0, len(planar), 4):
        # Pack 4 bytes little-endian: byte[0] -> bits 7:0
        w = (int(planar[i])     |
             (int(planar[i+1]) <<  8) |
             (int(planar[i+2]) << 16) |
             (int(planar[i+3]) << 24))
        words.append(w)

    lines = [f"{w:08X}," for w in words[:-1]]
    lines.append(f"{words[-1]:08X};")

    path.write_text(
        "memory_initialization_radix=16;\n"
        "memory_initialization_vector=\n"
        + "\n".join(lines)
        + "\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True, help="Input photo (JPEG/PNG)")
    parser.add_argument("--out",   default="image",
                        help="Output prefix (default: image → image.bin + image.coe)")
    args = parser.parse_args()

    arr = preprocess(args.image)
    assert arr.shape == (224, 224, 3), f"Unexpected shape: {arr.shape}"

    bin_path = Path(args.out + ".bin")
    coe_path = Path(args.out + ".coe")

    write_bin(bin_path, arr)
    write_coe(coe_path, arr)

    n_pixels = 224 * 224
    print(f"Written: {bin_path}  ({bin_path.stat().st_size} bytes)")
    print(f"Written: {coe_path}  ({len(list(open(coe_path))) - 2} words + 2 header lines)")
    print(f"  Shape : 224x224x3 planar (R then G then B)")
    print(f"  Use   : dow -data {bin_path} 0x10000000   (in XSCT, fast)")
    print(f"  Or    : source load_image.tcl              (uses image.coe, slower)")


if __name__ == "__main__":
    main()
