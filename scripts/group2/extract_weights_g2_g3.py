"""
extract_weights_g2_g3.py  --  Path A Step 5: Weight Extraction for ZU19EG
==========================================================================
Loads ShuffleNet V2 x1.0 (pretrained), folds BatchNorm into all relevant
conv layers, quantizes to per-layer widths (Ch 6.2.5), and writes hex init
files for the BRAM ROM modules built in Step 6.

RUN (from project root N:\\GP\\shufflenet_rtl\\):
    python scripts/group2/extract_weights_g2_g3.py

OUTPUT FILES (relative to project root):
  rtl/group2/weights/g2_dw_weights.hex   -- DW weights  ROM depth=16    width=7832b  1958 hex/line
  rtl/group2/weights/g2_dw_biases.hex    -- DW biases   ROM depth=16    width=870b   218 hex/line
  rtl/group2/weights/g2_pw_weights.hex   -- PW weights  ROM depth=320   width=7656b  1914 hex/line
  rtl/group2/weights/g2_pw_biases.hex    -- PW biases   ROM depth=16    width=754b   189 hex/line
  rtl/group3/weights/g3_pw_weights.hex   -- G3 PW weights ROM depth=1024  width=4176b  1044 hex/line
  rtl/group3/weights/g3_pw_biases.hex    -- G3 PW biases  ROM depth=64    width=240b    60 hex/line
  rtl/group3/weights/g3_fc_weights.hex   -- G3 FC weights ROM depth=32000 width=288b   72 hex/line
  rtl/group3/weights/g3_fc_biases.hex    -- G3 FC biases  ROM depth=1000  width=11b    3 hex/line
  rtl/group2/weights/g2_weights_verify.txt -- human-readable saturation summary
  rtl/group3/weights/g3_weights_verify.txt -- human-readable saturation summary

QUANTIZATION (Ch 6.2.5, shufflenet_pkg.vh):
  G2 DW weights : G2_DW_WW=15 bits, 8-bit fraction (scale=256)
  G2 DW biases  : DATA_W=15 bits,   8-bit fraction (scale=256)
  G2 PW weights : G2_PW_WW=11 bits, 9-bit fraction (scale=512)
  G2 PW biases  : G2_BIAS_W=13 bits, 9-bit fraction (scale=512)
  G3 PW weights : G3_PW_WW=9 bits,  8-bit fraction (scale=256)
  G3 PW biases  : DATA_W=15 bits,   8-bit fraction (scale=256)
  G3 FC weights : FC_WW=9 bits,     8-bit fraction (scale=256)
  G3 FC biases  : FC_BIAS_W=11 bits, 8-bit fraction (scale=256)

ROM ADDRESSING:
  g2_dw_weights  : ROM[loop]          bits (f*9+t)*15 +: 15  f=0..57  t=0..8
  g2_dw_biases   : ROM[loop]          bits f*15 +: 15  f=0..57  (all 58 packed)
  g2_pw_weights  : ROM[loop*20+step]  bits (f*12+c)*11 +: 11  f=0..57  c=0..11
  g2_pw_biases   : ROM[loop]          bits f*13 +: 13  f=0..57  (all 58 packed)
  g3_pw_weights  : ROM[fg*16+step]    bits (f*29+c)*9 +: 9    f=0..15  c=0..28
  g3_pw_biases   : ROM[fg]            bits f*15 +: 15  f=0..15  (all 16 packed)
  g3_fc_weights  : ROM[cls*32+step]   bits c*9 +: 9            c=0..31
  g3_fc_biases   : ROM[cls]           one 11-bit entry per class

SIMPLIFIED ARCHITECTURE NOTE:
  - G2 DW : first 58 of 58/116/232 DW filters; loops 4-15 drop the rest
  - G2 PW : first 58 output filters; input channels limited by N_ACC*12 per loop
      Loop 0: N_ACC=2 (24ch used of 58), Loops 1-4: N_ACC=5 (58+2 zeros),
      Loops 5-12: N_ACC=10 (116+4 zeros), Loops 13-15: N_ACC=20 (232+8 zeros)
  - G3 PW : acc step s maps to G2 loop s PW output (conv5 in-ch s*29..s*29+28)
  - G3 FC : 32 FC channels per step, 32 steps cover all 1024 avgpool outputs
"""

import os
import sys
import copy
import math
import numpy as np

try:
    import torch
    import torchvision
    from torchvision import models
except ImportError as e:
    print(f"ERROR: {e}\nInstall: pip install torch torchvision")
    sys.exit(1)

print(f"PyTorch     : {torch.__version__}")
print(f"Torchvision : {torchvision.__version__}")

# ============================================================
# Hardware parameters -- MUST match shufflenet_pkg.vh
# ============================================================
G2_DW_FILT  = 58    # G2_DW_PAR_FILT
G2_PW_FILT  = 58    # G2_PW_PAR_FILT
G2_PW_CHAN  = 12    # G2_PW_PAR_CHAN (reduced from 29 for ZU19EG)
G3_PW_FILT  = 16    # G3_PW_PAR_FILT
G3_PW_CHAN  = 29    # G3_PW_PAR_CHAN
G3_FC_CHAN  = 32    # G3_FC_PAR_CHAN
N_LOOPS     = 16    # total Group 2 shuffle blocks
MAX_STEPS   = 20    # max N_ACC across all loop configs (cfg5 = 20)
G3_N_ACC    = 16    # ceil(464/29) = 16 accumulation steps for conv5
G3_N_FG     = 64    # ceil(1024/16) = 64 filter groups for conv5
G3_FC_CLS   = 1000  # ImageNet classes
G3_FC_STEPS = 32    # ceil(1024/32) = 32 FC accumulation steps

# N_ACC per loop (matches group2_ctrl.v cfg0-5 assignments)
# cfg0=2, cfg1=5, cfg2=5, cfg3=10, cfg4=10, cfg5=20
LOOP_N_ACC = [2, 5, 5, 5, 5, 10, 10, 10, 10, 10, 10, 10, 10, 20, 20, 20]
assert len(LOOP_N_ACC) == N_LOOPS

# ============================================================
# Quantization helpers (Ch 6.2.5)
# ============================================================
class Quantizer:
    def __init__(self, bits, frac):
        self.bits  = bits
        self.frac  = frac
        self.scale = 1 << frac
        self.lo    = -(1 << (bits - 1))
        self.hi    =  (1 << (bits - 1)) - 1
        self.mask  =  (1 << bits) - 1
        self.max_float = self.hi  / self.scale
        self.min_float = self.lo  / self.scale

    def __call__(self, x):
        v = int(round(float(x) * self.scale))
        v = max(self.lo, min(self.hi, v))
        return v & self.mask

    def saturated(self, x):
        return float(x) > self.max_float or float(x) < self.min_float

Q_DW_W   = Quantizer(15, 8)   # G2 DW weights:  G2_DW_WW=15,   8-bit frac
Q_DW_B   = Quantizer(15, 8)   # G2 DW biases:   DATA_W=15,     8-bit frac
Q_PW_W   = Quantizer(11, 9)   # G2 PW weights:  G2_PW_WW=11,   9-bit frac
Q_PW_B   = Quantizer(13, 9)   # G2 PW biases:   G2_BIAS_W=13,  9-bit frac
Q_G3PW_W = Quantizer( 9, 8)   # G3 PW weights:  G3_PW_WW=9,    8-bit frac
Q_G3PW_B = Quantizer(15, 8)   # G3 PW biases:   DATA_W=15,     8-bit frac
Q_FC_W   = Quantizer( 9, 8)   # G3 FC weights:  FC_WW=9,       8-bit frac
Q_FC_B   = Quantizer(11, 8)   # G3 FC biases:   FC_BIAS_W=11,  8-bit frac

# ============================================================
# BN folding: W_new = W * (gamma/sqrt(var+eps))
#             b_new = gamma/sqrt(var+eps) * (b - mu) + beta
# ============================================================
def fold_conv_bn(conv, bn):
    conv  = copy.deepcopy(conv)
    scale = bn.weight.data / torch.sqrt(bn.running_var + bn.eps)
    conv.weight = torch.nn.Parameter(
        conv.weight.data * scale.view(-1, 1, 1, 1))
    bias = (conv.bias.data if conv.bias is not None
            else torch.zeros(conv.weight.shape[0], device=conv.weight.device))
    conv.bias = torch.nn.Parameter(
        scale * (bias - bn.running_mean) + bn.bias.data)
    return conv

# ============================================================
# Pack helpers
# ============================================================
def pack_word(vals, bits_each):
    """Pack a list of unsigned ints into one big integer, LSB first."""
    word = 0
    for i, v in enumerate(vals):
        word |= (int(v) << (i * bits_each))
    return word

def word_to_hex(word, total_bits):
    """Format integer as hex string with ceil(total_bits/4) uppercase digits."""
    n_hex = math.ceil(total_bits / 4)
    return format(word, f'0{n_hex}X')

# ============================================================
# Load model
# ============================================================
print("\nLoading ShuffleNet V2 x1.0 (pretrained)...")
model = models.shufflenet_v2_x1_0(weights='DEFAULT').eval()
print("  Loaded.\n")

# Sanity check: verify conv5 and FC dimensions
assert model.conv5[0].in_channels  == 464,  "conv5 in_channels mismatch"
assert model.conv5[0].out_channels == 1024, "conv5 out_channels mismatch"
assert model.fc.in_features  == 1024, "FC in_features mismatch"
assert model.fc.out_features == 1000, "FC out_features mismatch"

# Fold BN into conv5
conv5_folded = fold_conv_bn(model.conv5[0], model.conv5[1])
conv5_w = conv5_folded.weight.detach().numpy()  # [1024, 464, 1, 1]
conv5_b = conv5_folded.bias.detach().numpy()    # [1024]

# FC (no BN -- Linear layer has its own bias)
fc_w = model.fc.weight.detach().numpy()   # [1000, 1024]
fc_b = model.fc.bias.detach().numpy()     # [1000]

print(f"conv5 weight shape : {conv5_w.shape}")
print(f"FC    weight shape : {fc_w.shape}")

# ============================================================
# Extract all 16 Group 2 loop weights (DW + PW2, BN-folded)
# PyTorch branch2 layout: [PW1, BN, ReLU, DW, BN, PW2, BN, ReLU]
# We use: DW = branch2[3], BN_DW = branch2[4]
#         PW2= branch2[5], BN_PW2= branch2[6]
# ============================================================
print("Folding BN into G2 DW and PW2 weights for all 16 loops...")
loops = []
for stage in [model.stage2, model.stage3, model.stage4]:
    for block in stage:
        b2       = block.branch2
        dw_f     = fold_conv_bn(b2[3], b2[4])
        pw2_f    = fold_conv_bn(b2[5], b2[6])
        loops.append({
            'dw_w':  dw_f.weight.detach().numpy(),    # [N, 1, 3, 3]  N=58/116/232
            'dw_b':  dw_f.bias.detach().numpy(),      # [N]
            'pw2_w': pw2_f.weight.detach().numpy(),   # [M, M, 1, 1]  M=58/116/232
            'pw2_b': pw2_f.bias.detach().numpy(),     # [M]
        })
assert len(loops) == N_LOOPS, f"Expected 16 loops, got {len(loops)}"
print(f"  DW  channel counts per loop: {[l['dw_w'].shape[0] for l in loops]}")
print(f"  PW2 in_ch    counts per loop: {[l['pw2_w'].shape[1] for l in loops]}\n")

# ============================================================
# Paths
# ============================================================
script_dir = os.path.dirname(os.path.abspath(__file__))
proj_root  = os.path.abspath(os.path.join(script_dir, '..', '..'))

g2_dir = os.path.join(proj_root, 'rtl', 'group2', 'weights')
g3_dir = os.path.join(proj_root, 'rtl', 'group3', 'weights')
os.makedirs(g2_dir, exist_ok=True)
os.makedirs(g3_dir, exist_ok=True)

p = {
    'g2_dw_w':   os.path.join(g2_dir, 'g2_dw_weights.hex'),
    'g2_dw_b':   os.path.join(g2_dir, 'g2_dw_biases.hex'),
    'g2_pw_w':   os.path.join(g2_dir, 'g2_pw_weights.hex'),
    'g2_pw_b':   os.path.join(g2_dir, 'g2_pw_biases.hex'),
    'g3_pw_w':   os.path.join(g3_dir, 'g3_pw_weights.hex'),
    'g3_pw_b':   os.path.join(g3_dir, 'g3_pw_biases.hex'),
    'g3_fc_w':   os.path.join(g3_dir, 'g3_fc_weights.hex'),
    'g3_fc_b':   os.path.join(g3_dir, 'g3_fc_biases.hex'),
    'g2_verify': os.path.join(g2_dir, 'g2_weights_verify.txt'),
    'g3_verify': os.path.join(g3_dir, 'g3_weights_verify.txt'),
}

# ============================================================
# G2 DW weights ROM (depth=16, width=7832 bits -- 1958 hex/line)
# ROM[loop] = packed word; weight[f][t] at bits (f*9+t)*15 +: 15
# Tap order: t=0..(8) = [r0c0, r0c1, r0c2, r1c0, ..., r2c2]
# DW biases ROM (depth=16, width=870 bits -- 218 hex/line)
# ROM[loop] = packed word; bias[f] at bits f*15 +: 15 (f=0..57)
# ============================================================
print("Writing G2 DW weights + biases...")
dw_w_sat = dw_b_sat = 0

with open(p['g2_dw_w'], 'w') as fw, open(p['g2_dw_b'], 'w') as fb:
    for lp in range(N_LOOPS):
        dw_w_np = loops[lp]['dw_w'][:G2_DW_FILT, 0, :, :]  # [58,3,3]
        dw_b_np = loops[lp]['dw_b'][:G2_DW_FILT]            # [58]

        # Pack all 58*9 weights into one 7832-bit word
        word = 0
        for f in range(G2_DW_FILT):
            for t in range(9):
                r, c = t // 3, t % 3
                val  = float(dw_w_np[f, r, c])
                if Q_DW_W.saturated(val):
                    dw_w_sat += 1
                w = Q_DW_W(val)
                word |= (w << ((f * 9 + t) * 15))
        fw.write(word_to_hex(word, 7832) + '\n')   # 1958 hex chars

        # Pack all 58 biases for this loop into one 870-bit word
        bword = 0
        for f in range(G2_DW_FILT):
            val = float(dw_b_np[f])
            if Q_DW_B.saturated(val):
                dw_b_sat += 1
            b = Q_DW_B(val)
            bword |= (b << (f * 15))
        fb.write(word_to_hex(bword, 870) + '\n')   # 218 hex chars

print(f"  DW weight sat : {dw_w_sat} / {N_LOOPS * G2_DW_FILT * 9}")
print(f"  DW bias   sat : {dw_b_sat} / {N_LOOPS * G2_DW_FILT}")
print(f"  {p['g2_dw_w']}")
print(f"  {p['g2_dw_b']}\n")

# ============================================================
# G2 PW weights ROM (depth=320, width=7656 bits -- 1914 hex/line)
# ROM[loop*20 + step] = packed word; weight[f][c] at bits (f*12+c)*11 +: 11
# Channels beyond PyTorch in_channels are zero-padded.
# PW biases ROM (depth=16, width=754 bits -- 189 hex/line)
# ROM[loop] = packed word; bias[f] at bits f*13 +: 13 (f=0..57)
# ============================================================
print("Writing G2 PW weights + biases...")
pw_w_sat = pw_b_sat = 0

with open(p['g2_pw_w'], 'w') as fw, open(p['g2_pw_b'], 'w') as fb:
    for lp in range(N_LOOPS):
        pw2_w_np = loops[lp]['pw2_w'][:G2_PW_FILT, :, 0, 0]  # [58, M]
        pw2_b_np = loops[lp]['pw2_b'][:G2_PW_FILT]            # [58]
        n_in_ch  = pw2_w_np.shape[1]                           # 58, 116, or 232

        for step in range(MAX_STEPS):
            word = 0
            for f in range(G2_PW_FILT):
                for c in range(G2_PW_CHAN):
                    actual_ch = step * G2_PW_CHAN + c
                    if actual_ch < n_in_ch:
                        val = float(pw2_w_np[f, actual_ch])
                        if Q_PW_W.saturated(val):
                            pw_w_sat += 1
                        w = Q_PW_W(val)
                    else:
                        w = 0   # zero-pad for channels beyond model in_channels
                    word |= (w << ((f * G2_PW_CHAN + c) * 11))
            fw.write(word_to_hex(word, 7656) + '\n')   # 1914 hex chars

        # Pack all 58 biases for this loop into one 754-bit word
        bword = 0
        for f in range(G2_PW_FILT):
            val = float(pw2_b_np[f])
            if Q_PW_B.saturated(val):
                pw_b_sat += 1
            b = Q_PW_B(val)
            bword |= (b << (f * 13))
        fb.write(word_to_hex(bword, 754) + '\n')   # 189 hex chars

print(f"  PW weight sat : {pw_w_sat} / {N_LOOPS * MAX_STEPS * G2_PW_FILT * G2_PW_CHAN}")
print(f"  PW bias   sat : {pw_b_sat} / {N_LOOPS * G2_PW_FILT}")
print(f"  {p['g2_pw_w']}")
print(f"  {p['g2_pw_b']}\n")

# ============================================================
# G3 PW weights ROM (depth=1024, width=4176 bits -- 1044 hex/line)
# ROM[fg*16 + step] = packed word; weight[f][c] at bits (f*29+c)*9 +: 9
# conv5 input channel mapping: acc step s = G2 loop s output (s*29..s*29+28)
# G3 PW biases ROM (depth=64, width=240 bits -- 60 hex/line)
# ROM[fg] = packed word; bias[f] at bits f*15 +: 15 (f=0..15)
# ============================================================
print("Writing G3 PW (conv5) weights + biases...")
g3pw_w_sat = g3pw_b_sat = 0

with open(p['g3_pw_w'], 'w') as fw, open(p['g3_pw_b'], 'w') as fb:
    for fg in range(G3_N_FG):
        for step in range(G3_N_ACC):
            word = 0
            for f in range(G3_PW_FILT):
                out_filt = fg * G3_PW_FILT + f
                for c in range(G3_PW_CHAN):
                    in_ch = step * G3_PW_CHAN + c
                    val   = float(conv5_w[out_filt, in_ch, 0, 0])
                    if Q_G3PW_W.saturated(val):
                        g3pw_w_sat += 1
                    w = Q_G3PW_W(val)
                    word |= (w << ((f * G3_PW_CHAN + c) * 9))
            fw.write(word_to_hex(word, 4176) + '\n')   # 1044 hex chars

        # Pack all 16 biases for this filter_group into one 240-bit word
        bword = 0
        for f in range(G3_PW_FILT):
            out_filt = fg * G3_PW_FILT + f
            val = float(conv5_b[out_filt])
            if Q_G3PW_B.saturated(val):
                g3pw_b_sat += 1
            b = Q_G3PW_B(val)
            bword |= (b << (f * 15))
        fb.write(word_to_hex(bword, 240) + '\n')   # 60 hex chars

print(f"  G3 PW weight sat : {g3pw_w_sat} / {G3_N_FG * G3_N_ACC * G3_PW_FILT * G3_PW_CHAN}")
print(f"  G3 PW bias   sat : {g3pw_b_sat} / {G3_N_FG * G3_PW_FILT}")
print(f"  {p['g3_pw_w']}")
print(f"  {p['g3_pw_b']}\n")

# ============================================================
# G3 FC weights ROM (depth=32000, width=288 bits -- 72 hex/line)
# ROM[cls*32 + step] = packed word; weight[c] at bits c*9 +: 9
# G3 FC biases ROM (depth=1000, width=11 bits -- 3 hex/line)
# ROM[cls] = quantized FC bias
# ============================================================
print("Writing G3 FC weights + biases...")
fc_w_sat = fc_b_sat = 0

with open(p['g3_fc_w'], 'w') as fw, open(p['g3_fc_b'], 'w') as fb:
    for cls in range(G3_FC_CLS):
        for step in range(G3_FC_STEPS):
            word = 0
            for c in range(G3_FC_CHAN):
                in_ch = step * G3_FC_CHAN + c
                val   = float(fc_w[cls, in_ch])
                if Q_FC_W.saturated(val):
                    fc_w_sat += 1
                w = Q_FC_W(val)
                word |= (w << (c * 9))
            fw.write(word_to_hex(word, 288) + '\n')    # 72 hex chars

        val = float(fc_b[cls])
        if Q_FC_B.saturated(val):
            fc_b_sat += 1
        b = Q_FC_B(val)
        fb.write(f'{b:03X}\n')

print(f"  FC weight sat : {fc_w_sat} / {G3_FC_CLS * G3_FC_STEPS * G3_FC_CHAN}")
print(f"  FC bias   sat : {fc_b_sat} / {G3_FC_CLS}")
print(f"  {p['g3_fc_w']}")
print(f"  {p['g3_fc_b']}\n")

# ============================================================
# Verify files -- human-readable sample weights for inspection
# ============================================================
print("Writing verify files...")

with open(p['g2_verify'], 'w') as fv:
    fv.write("G2 Weight Extraction Verify  (extract_weights_g2_g3.py)\n")
    fv.write("=" * 65 + "\n\n")
    fv.write("QUANTIZATION FORMATS\n")
    fv.write(f"  DW  weights : {Q_DW_W.bits}-bit  frac={Q_DW_W.frac}  "
             f"scale={Q_DW_W.scale}  range=[{Q_DW_W.min_float:.4f}, {Q_DW_W.max_float:.4f}]\n")
    fv.write(f"  DW  biases  : {Q_DW_B.bits}-bit  frac={Q_DW_B.frac}  "
             f"scale={Q_DW_B.scale}  range=[{Q_DW_B.min_float:.4f}, {Q_DW_B.max_float:.4f}]\n")
    fv.write(f"  PW  weights : {Q_PW_W.bits}-bit  frac={Q_PW_W.frac}  "
             f"scale={Q_PW_W.scale}  range=[{Q_PW_W.min_float:.4f}, {Q_PW_W.max_float:.4f}]\n")
    fv.write(f"  PW  biases  : {Q_PW_B.bits}-bit  frac={Q_PW_B.frac}  "
             f"scale={Q_PW_B.scale}  range=[{Q_PW_B.min_float:.4f}, {Q_PW_B.max_float:.4f}]\n\n")
    fv.write("SATURATION COUNTS\n")
    fv.write(f"  DW weights : {dw_w_sat} / {N_LOOPS * G2_DW_FILT * 9}\n")
    fv.write(f"  DW biases  : {dw_b_sat} / {N_LOOPS * G2_DW_FILT}\n")
    fv.write(f"  PW weights : {pw_w_sat} / {N_LOOPS * MAX_STEPS * G2_PW_FILT * G2_PW_CHAN}\n")
    fv.write(f"  PW biases  : {pw_b_sat} / {N_LOOPS * G2_PW_FILT}\n\n")
    fv.write("LOOP CHANNEL COUNTS\n")
    fv.write(f"  {'Loop':>4}  {'Stage':>7}  {'N_ACC':>5}  {'DW_ch':>5}  {'PW2_in':>6}  {'PW2_used':>8}\n")
    fv.write("-" * 50 + "\n")
    stg_map = (['stage2'] * 4) + (['stage3'] * 8) + (['stage4'] * 4)
    for lp in range(N_LOOPS):
        dw_ch    = loops[lp]['dw_w'].shape[0]
        pw2_in   = loops[lp]['pw2_w'].shape[1]
        pw2_used = min(LOOP_N_ACC[lp] * G2_PW_CHAN, pw2_in)
        fv.write(f"  {lp:>4}  {stg_map[lp]:>7}  {LOOP_N_ACC[lp]:>5}  "
                 f"{dw_ch:>5}  {pw2_in:>6}  {pw2_used:>8}\n")
    fv.write("\nSAMPLE WEIGHTS (loop=0, filter=0)\n")
    dw0 = loops[0]['dw_w'][0, 0, :, :]  # [3,3] -- shape is [N,1,3,3]
    fv.write("  DW filter 0 kernel (3x3, float):\n")
    for r in range(3):
        fv.write("    " + "  ".join(f"{float(dw0[r,c]):+8.5f}" for c in range(3)) + "\n")
    fv.write("  DW filter 0 bias: " +
             f"{float(loops[0]['dw_b'][0]):+8.5f} -> Q={Q_DW_B(float(loops[0]['dw_b'][0])):04X}\n")
    fv.write("  PW2 filter 0 bias: " +
             f"{float(loops[0]['pw2_b'][0]):+8.5f} -> Q={Q_PW_B(float(loops[0]['pw2_b'][0])):04X}\n")
    fv.write("\nSAMPLE WEIGHTS (loop=4, filter=0) [stage3 first block]\n")
    dw4 = loops[4]['dw_w'][0, 0, :, :]
    fv.write("  DW filter 0 kernel (3x3, float):\n")
    for r in range(3):
        fv.write("    " + "  ".join(f"{float(dw4[r,c]):+8.5f}" for c in range(3)) + "\n")

with open(p['g3_verify'], 'w') as fv:
    fv.write("G3 Weight Extraction Verify  (extract_weights_g2_g3.py)\n")
    fv.write("=" * 65 + "\n\n")
    fv.write("QUANTIZATION FORMATS\n")
    fv.write(f"  G3 PW weights : {Q_G3PW_W.bits}-bit  frac={Q_G3PW_W.frac}  "
             f"scale={Q_G3PW_W.scale}  range=[{Q_G3PW_W.min_float:.4f}, {Q_G3PW_W.max_float:.4f}]\n")
    fv.write(f"  G3 PW biases  : {Q_G3PW_B.bits}-bit  frac={Q_G3PW_B.frac}  "
             f"scale={Q_G3PW_B.scale}  range=[{Q_G3PW_B.min_float:.4f}, {Q_G3PW_B.max_float:.4f}]\n")
    fv.write(f"  FC weights    : {Q_FC_W.bits}-bit   frac={Q_FC_W.frac}  "
             f"scale={Q_FC_W.scale}  range=[{Q_FC_W.min_float:.4f}, {Q_FC_W.max_float:.4f}]\n")
    fv.write(f"  FC biases     : {Q_FC_B.bits}-bit  frac={Q_FC_B.frac}  "
             f"scale={Q_FC_B.scale}  range=[{Q_FC_B.min_float:.4f}, {Q_FC_B.max_float:.4f}]\n\n")
    fv.write("SATURATION COUNTS\n")
    fv.write(f"  G3 PW weights : {g3pw_w_sat} / {G3_N_FG * G3_N_ACC * G3_PW_FILT * G3_PW_CHAN}\n")
    fv.write(f"  G3 PW biases  : {g3pw_b_sat} / {G3_N_FG * G3_PW_FILT}\n")
    fv.write(f"  FC weights    : {fc_w_sat} / {G3_FC_CLS * G3_FC_STEPS * G3_FC_CHAN}\n")
    fv.write(f"  FC biases     : {fc_b_sat} / {G3_FC_CLS}\n\n")
    fv.write("CONV5 DIMENSIONS\n")
    fv.write(f"  Weight : {conv5_w.shape}  (out=1024, in=464)\n")
    fv.write(f"  Filter groups: {G3_N_FG} x {G3_PW_FILT} = 1024 output filters\n")
    fv.write(f"  Acc steps    : {G3_N_ACC} x {G3_PW_CHAN} = 464 input channels\n\n")
    fv.write("SAMPLE WEIGHTS (conv5 fg=0 step=0 filt=0)\n")
    fv.write("  conv5[0, 0..4, 0, 0] (float): "
             + "  ".join(f"{float(conv5_w[0,c,0,0]):+.4f}" for c in range(5)) + "\n")
    fv.write("  FC class 0 weights [0..7] (float): "
             + "  ".join(f"{float(fc_w[0,c]):+.4f}" for c in range(8)) + "\n")
    fv.write(f"  FC class 0 bias (float): {float(fc_b[0]):+.4f} "
             f"-> Q={Q_FC_B(float(fc_b[0])):03X}\n")

print(f"  {p['g2_verify']}")
print(f"  {p['g3_verify']}\n")

# ============================================================
# Summary
# ============================================================
print("=" * 60)
print("STEP 5/7 EXTRACTION COMPLETE")
print("=" * 60)
print()
print("G2 ROM files:")
print(f"  g2_dw_weights.hex  : {N_LOOPS} entries x 1958 hex  (depth=16,  width=7832b)")
print(f"  g2_dw_biases.hex   : {N_LOOPS} entries x 218 hex   (depth=16,  width=870b)")
print(f"  g2_pw_weights.hex  : {N_LOOPS*MAX_STEPS} entries x 1914 hex  (depth=320, width=7656b)")
print(f"  g2_pw_biases.hex   : {N_LOOPS} entries x 189 hex   (depth=16,  width=754b)")
print()
print("G3 ROM files:")
print(f"  g3_pw_weights.hex  : {G3_N_FG*G3_N_ACC} entries x 1044 hex  (depth=1024, width=4176b)")
print(f"  g3_pw_biases.hex   : {G3_N_FG} entries x 60 hex    (depth=64,   width=240b)")
print(f"  g3_fc_weights.hex  : {G3_FC_CLS*G3_FC_STEPS} entries x 72 hex    (depth=32000, width=288b)")
print(f"  g3_fc_biases.hex   : {G3_FC_CLS} entries x 3 hex    (depth=1000, width=11b)")
print()
print("Saturation summary:")
print(f"  G2 DW  weights: {dw_w_sat}   G2 DW  biases: {dw_b_sat}")
print(f"  G2 PW  weights: {pw_w_sat}  G2 PW  biases: {pw_b_sat}")
print(f"  G3 PW  weights: {g3pw_w_sat}  G3 PW  biases: {g3pw_b_sat}")
print(f"  G3 FC  weights: {fc_w_sat}  G3 FC  biases: {fc_b_sat}")
print()
print("Next: Step 8 -- build AXI slave for PS image load.")
