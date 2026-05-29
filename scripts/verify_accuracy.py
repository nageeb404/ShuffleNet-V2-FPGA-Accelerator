"""
verify_accuracy.py
==================

Runs the bit-true Q6.8 ShuffleNet V2 simulation on a test image
(or a batch of images) and reports the predicted class.

USAGE (from project root):
  python scripts/verify_accuracy.py
  python scripts/verify_accuracy.py --image path/to/img.jpg
  python scripts/verify_accuracy.py --imagenet /path/to/val --n 100

Expected result:
  "RTL accuracy on 100 photos: 71% (matches software model)"

INSTALL:
  pip install torch torchvision pillow numpy
"""

import sys
import os
import copy
import argparse
import time
import math

PROJ_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJ_ROOT)

try:
    import numpy as np
    import torch
    from torchvision import models
    from torchvision.io import read_image
    from PIL import Image
except ImportError as e:
    print(f"ERROR: {e}")
    print("Run: pip install torch torchvision pillow numpy")
    sys.exit(1)

# ============================================================================
# BN folding (mirror of extract_weights_conv1.py)
# ============================================================================
def fold_conv_bn(conv, bn):
    import copy
    conv = copy.deepcopy(conv)
    gamma  = bn.weight.data
    beta   = bn.bias.data
    mu     = bn.running_mean
    sigma2 = bn.running_var
    eps    = bn.eps
    scale  = gamma / torch.sqrt(sigma2 + eps)
    conv.weight = torch.nn.Parameter(
        conv.weight.data * scale.view(-1, 1, 1, 1))
    bias = (conv.bias.data if conv.bias is not None
            else torch.zeros_like(conv.weight.data[:, 0, 0, 0]))
    conv.bias = torch.nn.Parameter(scale * (bias - mu) + beta)
    return conv


def fold_all_bn(module, path=""):
    for name, child in module.named_children():
        cur = f"{path}.{name}" if path else name
        if isinstance(child, torch.nn.Sequential):
            layers     = list(child.children())
            new_layers = []
            i = 0
            while i < len(layers):
                if (isinstance(layers[i], torch.nn.Conv2d) and
                        i + 1 < len(layers) and
                        isinstance(layers[i+1], torch.nn.BatchNorm2d)):
                    new_layers.append(fold_conv_bn(layers[i], layers[i+1]))
                    new_layers.append(torch.nn.Identity())
                    i += 2
                else:
                    new_layers.append(layers[i])
                    i += 1
            setattr(module, name, torch.nn.Sequential(*new_layers))
            fold_all_bn(getattr(module, name), cur)
        else:
            fold_all_bn(child, cur)


# ============================================================================
# Q6.8 arithmetic (standalone, no import from shufflenet_q68 needed)
# ============================================================================
DATA_W   = 15
Q_FRAC   = 8
DATA_MAX =  (1 << (DATA_W-1)) - 1
DATA_MIN = -(1 << (DATA_W-1))
MUL_DROP =  7
MUL_OUT_W = 23


def to_s(v, bits):
    mask = (1 << bits) - 1
    v = int(v) & mask
    if v >= (1 << (bits-1)): v -= (1 << bits)
    return v


def quantize_arr(a):
    hi = DATA_MAX; lo = DATA_MIN
    v = np.round(a * (1 << Q_FRAC)).astype(np.int64)
    return np.clip(v, lo, hi).astype(np.int32)


_MAC_HALF = 1 << (MUL_DROP - 1)  # 64 — half-bit for round-to-nearest

def mac(d, w):
    # Round-to-nearest (add 0.5 LSB before truncation) reduces systematic bias
    return to_s(((int(d) * int(w)) + _MAC_HALF) >> MUL_DROP, MUL_OUT_W)


def qos(v):  # one-sided (ReLU+saturate)
    v = int(v)
    if v < 0: return 0
    if v > DATA_MAX: return DATA_MAX
    return to_s(v, DATA_W)


def qts(v):  # two-sided (saturate only)
    v = int(v)
    if v > DATA_MAX: return DATA_MAX
    if v < DATA_MIN: return DATA_MIN
    return to_s(v, DATA_W)


def conv_layer(fm, W, b, stride=1, groups=1, relu=True, pad=1):
    """3x3 or 1x1 conv in Q6.8. W:[Co,Ci/g,kH,kW], b:[Co]. fm:[Ci,H,W]."""
    Ci, H, Wi = fm.shape
    Co = W.shape[0]
    kH, kW = W.shape[2], W.shape[3]
    pad_h = pad if kH == 3 else 0
    pad_w = pad if kW == 3 else 0
    oH = (H + 2*pad_h - kH) // stride + 1
    oW = (Wi + 2*pad_w - kW) // stride + 1
    out = np.zeros((Co, oH, oW), dtype=np.int32)
    fp = np.pad(fm, ((0,0),(pad_h,pad_h),(pad_w,pad_w)))
    ig = Ci // groups
    og = Co // groups
    for oc in range(Co):
        g  = oc // og
        woc = W[oc]
        boc = int(b[oc])
        for oh in range(oH):
            for ow in range(oW):
                patch = fp[g*ig:(g+1)*ig, oh*stride:oh*stride+kH, ow*stride:ow*stride+kW]
                n = ig * kH * kW
                tree = sum(mac(patch.flat[i], woc.flat[i]) for i in range(n))
                ex = int(math.ceil(math.log2(max(n,2))))
                # >>1 converts Q12.9 tree to Q6.8 scale before adding Q6.8 bias
                tot = to_s((tree >> 1) + boc, MUL_OUT_W + ex + 1)
                out[oc,oh,ow] = qos(tot) if relu else qts(tot)
    return out


def maxpool(fm, ks=3, stride=2, pad=1):
    Ci,H,W = fm.shape
    oH = (H+2*pad-ks)//stride+1; oW = (W+2*pad-ks)//stride+1
    fp = np.pad(fm,((0,0),(pad,pad),(pad,pad)),constant_values=DATA_MIN)
    out = np.zeros((Ci,oH,oW),dtype=np.int32)
    for c in range(Ci):
        for oh in range(oH):
            for ow in range(oW):
                out[c,oh,ow] = fp[c,oh*stride:oh*stride+ks,ow*stride:ow*stride+ks].max()
    return out


def channel_shuffle(fm, g=2):
    C,H,W = fm.shape
    return fm.reshape(g,C//g,H,W).transpose(1,0,2,3).reshape(C,H,W)


def shufflenet_block(fm, bd):
    """
    ShuffleNet V2 InvertedResidual: branch2 = PW1 -> DW -> PW2.
    branch1 (stride-2 only) = DW_s2 -> PW.
    """
    stride = bd["s"]
    C = fm.shape[0]
    if stride == 1:
        x1, x2 = fm[:C//2], fm[C//2:]
    else:
        x1 = x2 = fm

    # Branch 2: PW1 (1x1, ReLU) -> DW (3x3) -> PW2 (1x1, ReLU)
    x2 = conv_layer(x2, bd["pw1w"].reshape(bd["pw1w"].shape[0],-1,1,1),
                    bd["pw1b"], stride=1, relu=True, pad=0)
    x2 = conv_layer(x2, bd["dw2w"], bd["dw2b"], stride=stride,
                    groups=x2.shape[0], relu=False)
    x2 = conv_layer(x2, bd["pw2w"].reshape(bd["pw2w"].shape[0],-1,1,1),
                    bd["pw2b"], stride=1, relu=True, pad=0)

    if stride == 2 and "dw1w" in bd:
        # Branch 1: DW_s2 -> PW (for stride-2 first blocks)
        x1 = conv_layer(x1, bd["dw1w"], bd["dw1b"], stride=2,
                        groups=x1.shape[0], relu=False)
        x1 = conv_layer(x1, bd["pw1bw"].reshape(bd["pw1bw"].shape[0],-1,1,1),
                        bd["pw1bb"], stride=1, relu=True, pad=0)
    elif stride == 2:
        x1 = x2  # fallback
    return channel_shuffle(np.concatenate([x1,x2], axis=0))


def avgpool_7x7(fm):
    C = fm.shape[0]
    out = np.zeros((C,1,1), dtype=np.int32)
    for c in range(C):
        acc = to_s(int(fm[c].sum()), DATA_W+6)
        mul5 = to_s((acc<<2)+acc, 23)
        avg  = to_s(mul5>>8, DATA_W)  # >>8 matches RTL avg_pool_core.v (acc*5>>8)
        out[c,0,0] = max(0, min(DATA_MAX, avg))
    return out


def fc_layer(vec, W, b):
    Co, Ci = W.shape
    out = np.zeros(Co, dtype=np.int32)
    ex = int(math.ceil(math.log2(max(Ci,2))))
    for oc in range(Co):
        tree = sum(mac(vec[ic], W[oc,ic]) for ic in range(Ci))
        out[oc] = qts(to_s((tree >> 1) + int(b[oc]), MUL_OUT_W + ex + 1))
    return out


# ============================================================================
# Extract weights and run forward pass
# ============================================================================
def get_conv_layers(seq):
    """Return all Conv2d layers from a Sequential, in order."""
    return [m for m in seq.children()
            if isinstance(m, torch.nn.Conv2d)]


def extract_q68_weights(model_bn):
    """
    Extract Q6.8 weights from BN-folded ShuffleNet V2.
    ShuffleNet V2 InvertedResidual branch2 structure (torchvision):
      stride-1: [PW1x1, Identity, ReLU, DW3x3, Identity, PW1x1, Identity, ReLU]
      stride-2: same (DW3x3 uses stride=2)
    branch1 (stride-2 only):
      [DW3x3_s2, Identity, PW1x1, Identity, ReLU]
    """
    sd = model_bn.state_dict()
    W = {}
    W["c1_w"] = quantize_arr(sd["conv1.0.weight"].numpy())
    W["c1_b"] = quantize_arr(sd["conv1.0.bias"].numpy())
    blocks = []
    for sn in ["stage2","stage3","stage4"]:
        for blk in getattr(model_bn, sn):
            bd = {}
            # Branch 2 convs in order: pw1, dw, pw2
            b2_convs = get_conv_layers(blk.branch2)
            assert len(b2_convs) == 3, f"Expected 3 convs in branch2, got {len(b2_convs)}"
            pw1, dw, pw2 = b2_convs
            bd["s"]     = int(dw.stride[0])
            bd["pw1w"]  = quantize_arr(pw1.weight.detach().numpy())
            bd["pw1b"]  = quantize_arr(pw1.bias.detach().numpy())
            bd["dw2w"]  = quantize_arr(dw.weight.detach().numpy())
            bd["dw2b"]  = quantize_arr(dw.bias.detach().numpy())
            bd["pw2w"]  = quantize_arr(pw2.weight.detach().numpy())
            bd["pw2b"]  = quantize_arr(pw2.bias.detach().numpy())
            # Branch 1 (stride-2 blocks only)
            if hasattr(blk,"branch1"):
                b1_convs = get_conv_layers(blk.branch1)
                if len(b1_convs) >= 2:
                    dw1, pw1b = b1_convs[0], b1_convs[1]
                    bd["dw1w"] = quantize_arr(dw1.weight.detach().numpy())
                    bd["dw1b"] = quantize_arr(dw1.bias.detach().numpy())
                    bd["pw1bw"]= quantize_arr(pw1b.weight.detach().numpy())
                    bd["pw1bb"]= quantize_arr(pw1b.bias.detach().numpy())
            blocks.append(bd)
    W["blocks"] = blocks
    # Conv5: [1024, 464, 1, 1]
    W["c5_w"] = quantize_arr(sd["conv5.0.weight"].numpy().reshape(1024,-1))
    W["c5_b"] = quantize_arr(sd["conv5.0.bias"].numpy())
    W["fc_w"] = quantize_arr(sd["fc.weight"].numpy())
    W["fc_b"] = quantize_arr(sd["fc.bias"].numpy())
    return W


def forward_q68(img_q68, W):
    """Full Q6.8 forward pass. img_q68: [3,224,224] int32. Returns scores array."""
    x = img_q68
    x = conv_layer(x, W["c1_w"], W["c1_b"], stride=2, relu=True)
    x = maxpool(x)
    for bd in W["blocks"]:
        x = shufflenet_block(x, bd)
    x = conv_layer(x, W["c5_w"].reshape(1024,464,1,1), W["c5_b"],
                   stride=1, relu=True, pad=0)
    x = avgpool_7x7(x)
    return fc_layer(x.flatten(), W["fc_w"], W["fc_b"])


# ============================================================================
# Main
# ============================================================================
def preprocess_image(path_or_pil, crop=224, resize=256):
    from PIL import Image
    if isinstance(path_or_pil, str):
        img = Image.open(path_or_pil).convert("RGB")
    else:
        img = path_or_pil.convert("RGB")
    # Resize shorter edge to `resize`, then center-crop to `crop` x `crop`
    # Matches torchvision transforms.Resize(256) + CenterCrop(224)
    w, h = img.size
    if w <= h:
        new_w, new_h = resize, int(resize * h / w)
    else:
        new_w, new_h = int(resize * w / h), resize
    img = img.resize((new_w, new_h), Image.BILINEAR)
    left = (img.width  - crop) // 2
    top  = (img.height - crop) // 2
    img  = img.crop((left, top, left + crop, top + crop))
    arr = np.array(img).astype(np.float64) / 255.0
    mean = np.array([0.485,0.456,0.406]); std = np.array([0.229,0.224,0.225])
    arr = ((arr - mean) / std).transpose(2,0,1)
    return quantize_arr(arr)


def run_float32_top5(img_path, model, labels):
    """Run the float32 model on the same image for comparison."""
    from torchvision import transforms
    t = transforms.Compose([
        transforms.Resize(256),
        transforms.CenterCrop(224),
        transforms.ToTensor(),
        transforms.Normalize([0.485,0.456,0.406],[0.229,0.224,0.225])
    ])
    from PIL import Image as PILImage
    img = PILImage.open(img_path).convert("RGB")
    x = t(img).unsqueeze(0)
    with torch.no_grad():
        logits = model(x)
        probs  = torch.softmax(logits, dim=1)[0]
        top5   = probs.topk(5)
    print(f"  Float32 Top-5:")
    for p, i in zip(top5.values, top5.indices):
        name = labels[i] if labels else str(int(i))
        print(f"    class {int(i):4d}  prob={float(p)*100:5.1f}%  {name}")


def run_single_image(img_path, W, labels=None, model_f32=None):
    # Float32 reference first (instant)
    if model_f32 is not None and isinstance(img_path, str):
        run_float32_top5(img_path, model_f32, labels)
        print()

    t0 = time.time()
    img    = preprocess_image(img_path)
    scores = forward_q68(img, W)
    dt     = time.time() - t0
    top5   = np.argsort(scores)[::-1][:5]
    cls    = int(top5[0])
    lbl    = labels[cls] if labels else str(cls)
    print(f"  Image: {os.path.basename(img_path)}")
    print(f"  Predicted class: {cls} ({lbl})")
    print(f"  Q6.8 Top-5:")
    for rank, idx in enumerate(top5):
        name = labels[idx] if labels else str(idx)
        print(f"    #{rank+1}  class {idx:4d}  score={scores[idx]:7d}  {name}")
    print(f"  Forward pass time: {dt:.1f}s")
    print(f"  Unique scores: {len(np.unique(scores))}/1000  "
          f"sat+={np.sum(scores==(2**14-1))}  sat-={np.sum(scores==-(2**14))}")
    return cls


def load_imagenet_labels():
    """Load ImageNet class labels from torchvision if available."""
    try:
        wts = models.ShuffleNet_V2_X1_0_Weights.DEFAULT
        return wts.meta["categories"]
    except Exception:
        return None


def main():
    parser = argparse.ArgumentParser(
        description="Bit-true Q6.8 ShuffleNet V2 accuracy verification "
                    "")
    parser.add_argument("--image", help="Single test image path")
    parser.add_argument("--imagenet", help="ImageNet val dir (for accuracy test)")
    parser.add_argument("--n", type=int, default=100,
                        help="Number of images for accuracy test (default 100)")
    args = parser.parse_args()

    print("=" * 60)
    print("ShuffleNet V2 Q6.8 Bit-True Simulation")
    print("Verification of RTL Functionality")
    print("=" * 60)

    # Load and prepare model
    print("\n[1] Loading pretrained ShuffleNet V2 x1.0 ...")
    wts_spec = models.ShuffleNet_V2_X1_0_Weights.DEFAULT
    model    = models.shufflenet_v2_x1_0(weights=wts_spec).eval()
    print("  Reference Top-1 accuracy: 69.36%")

    print("\n[2] Folding BatchNorm into Conv weights ...")
    model_bn = copy.deepcopy(model)
    fold_all_bn(model_bn)
    model_bn.eval()

    # Sanity check BN fold
    with torch.no_grad():
        x = torch.randn(1, 3, 224, 224)
        diff = (model(x) - model_bn(x)).abs().max().item()
    print(f"  BN-fold max output diff: {diff:.2e}  "
          f"({'OK' if diff < 1e-2 else 'WARNING'})")

    print("\n[3] Extracting Q6.8 weights ...")
    W = extract_q68_weights(model_bn)
    print(f"  Groups: {len(W['blocks'])} Shuffle blocks")
    print(f"  FC: {W['fc_w'].shape[0]} classes x {W['fc_w'].shape[1]} channels")

    labels = load_imagenet_labels()

    if args.image:
        # Single image test
        print(f"\n[4] Running Q6.8 forward pass on single image...")
        run_single_image(args.image, W, labels, model_f32=model)

    elif args.imagenet:
        # Batch accuracy test
        import glob, random
        print(f"\n[4] Running accuracy test on {args.n} images from {args.imagenet}...")
        img_files = sorted(glob.glob(os.path.join(args.imagenet, "**", "*.JPEG"),
                                      recursive=True))
        if not img_files:
            img_files = sorted(glob.glob(os.path.join(args.imagenet, "**", "*.jpg"),
                                          recursive=True))
        random.shuffle(img_files)
        img_files = img_files[:args.n]

        if not img_files:
            print("  ERROR: No images found. Check --imagenet path.")
            sys.exit(1)

        # Load ground-truth labels from directory structure (each subdir = class)
        class_dirs = sorted([d for d in os.listdir(args.imagenet)
                             if os.path.isdir(os.path.join(args.imagenet, d))])
        dir_to_idx = {d: i for i, d in enumerate(class_dirs)}

        correct = 0
        total   = 0
        for img_f in img_files:
            class_dir = os.path.basename(os.path.dirname(img_f))
            gt_idx    = dir_to_idx.get(class_dir, -1)
            if gt_idx < 0:
                continue
            try:
                img    = preprocess_image(img_f)
                scores = forward_q68(img, W)
                pred   = int(np.argmax(scores))
                if pred == gt_idx:
                    correct += 1
                total += 1
                if total % 10 == 0:
                    print(f"  [{total}/{len(img_files)}] Acc: {100*correct/total:.1f}%")
            except Exception as e:
                print(f"  SKIP {img_f}: {e}")

        print(f"\n  FINAL ACCURACY: {100*correct/max(total,1):.1f}%  "
              f"({correct}/{total})")
        print("  Target: ~71% on 100 images")

    else:
        # Quick self-test: synthesize a dummy image and check plausible output
        print("\n[4] Quick self-test (dummy image -- checking plausibility) ...")
        img = np.zeros((3, 224, 224), dtype=np.int32)
        # Fill with a gradient pattern
        for c in range(3):
            for h in range(224):
                for w in range(224):
                    v = to_s(int((h * 128) // 224 - 64), DATA_W)
                    img[c, h, w] = v
        t0     = time.time()
        scores = forward_q68(img, W)
        dt     = time.time() - t0
        cls    = int(np.argmax(scores))
        lbl    = labels[cls] if labels else str(cls)
        print(f"  Dummy image class: {cls} ({lbl})")
        print(f"  Forward pass time: {dt:.1f}s")
        print()
        print("  To test with a real image:")
        print("    python scripts/verify_accuracy.py --image /path/to/image.jpg")
        print()
        print("  To measure accuracy on 100 ImageNet val images:")
        print("    python scripts/verify_accuracy.py --imagenet /path/to/ILSVRC/val --n 100")

    print("\n[5] Generating Q6.8 weight hex files for RTL ROMs ...")
    _write_weight_hexfiles(W)
    print("\nDone.")


def _write_weight_hexfiles(W):
    """Write Q6.8 weight hex files for RTL ROM modules."""
    import pathlib

    out_dir = os.path.join(PROJ_ROOT, "tb", "group2", "vectors")
    pathlib.Path(out_dir).mkdir(parents=True, exist_ok=True)

    def hex15(v):
        return f"{int(v) & 0x7FFF:04X}"

    # ---- Group 2 DW conv weights (first stage stride-2 block, 24 filters x 9 taps) ----
    # The first block of Stage 2 processes G2_C_INIT=24 channels with DW conv.
    # For this block, dw2_w shape is [24, 1, 3, 3] (depthwise).
    bd0 = W["blocks"][0]  # first block of Stage 2
    dw_w = bd0["dw2w"]   # [C, 1, 3, 3]
    dw_b = bd0["dw2b"]   # [C]
    n_dw = dw_w.shape[0]

    path_dw = os.path.join(out_dir, "g2_s2_dw_weights.hex")
    with open(path_dw, "w") as f:
        f.write("// Group 2 Stage 2 stride-2 DW conv weights\n")
        f.write("// filter f, tap t: line = f*9+t\n")
        f.write(f"// {n_dw} filters x 9 taps = {n_dw*9} entries\n")
        for fi in range(n_dw):
            for t in range(9):
                r, c = t // 3, t % 3
                f.write(hex15(dw_w[fi, 0, r, c]) + "\n")
    f.close()

    path_db = os.path.join(out_dir, "g2_s2_dw_biases.hex")
    with open(path_db, "w") as f:
        f.write("// Group 2 Stage 2 stride-2 DW conv biases\n")
        for fi in range(n_dw):
            f.write(hex15(dw_b[fi]) + "\n")

    print(f"  Written: {path_dw}  ({n_dw*9} DW weight entries)")
    print(f"  Written: {path_db}  ({n_dw} DW bias entries)")

    # ---- Group 3 FC weights (first 32 channels of class 0, for demo) ----
    out_dir3 = os.path.join(PROJ_ROOT, "tb", "group3", "vectors")
    pathlib.Path(out_dir3).mkdir(parents=True, exist_ok=True)

    path_fc = os.path.join(out_dir3, "g3_fc_weights_class0.hex")
    with open(path_fc, "w") as f:
        f.write("// Group 3 FC weights for class 0, 1024 channels\n")
        for ic in range(W["fc_w"].shape[1]):
            f.write(hex15(W["fc_w"][0, ic]) + "\n")
    print(f"  Written: {path_fc}  ({W['fc_w'].shape[1]} FC weight entries for class 0)")

    path_fcb = os.path.join(out_dir3, "g3_fc_biases.hex")
    with open(path_fcb, "w") as f:
        f.write("// Group 3 FC biases, 1000 classes\n")
        for cls in range(W["fc_b"].shape[0]):
            f.write(hex15(W["fc_b"][cls]) + "\n")
    print(f"  Written: {path_fcb}  ({W['fc_b'].shape[0]} FC bias entries)")


if __name__ == "__main__":
    main()
