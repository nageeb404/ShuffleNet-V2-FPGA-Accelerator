"""
Block diagrams for ShuffleNet V2 FPGA Accelerator.
Clean layout — no overlapping elements.
"""
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch

# ─── drawing helpers ──────────────────────────────────────────────────────────

def box(ax, x, y, w, h, title, sub='',
        fc='#D6EAF8', ec='#1A5276', lw=1.5, tfs=9, sfs=7.5, bold=False):
    p = FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.03',
                       facecolor=fc, edgecolor=ec, linewidth=lw, zorder=2)
    ax.add_patch(p)
    tw = 'bold' if bold else 'normal'
    if sub:
        ax.text(x+w/2, y+h*0.65, title, ha='center', va='center',
                fontsize=tfs, fontweight=tw, zorder=3)
        ax.text(x+w/2, y+h*0.28, sub, ha='center', va='center',
                fontsize=sfs, color='#444', zorder=3)
    else:
        ax.text(x+w/2, y+h/2, title, ha='center', va='center',
                fontsize=tfs, fontweight=tw, zorder=3)

def harrow(ax, x1, x2, y, col='#1A5276', lw=1.5, lbl='', lbl_above=True):
    ax.annotate('', xy=(x2, y), xytext=(x1, y),
                arrowprops=dict(arrowstyle='->', color=col, lw=lw,
                                mutation_scale=12), zorder=4)
    if lbl:
        dy = 0.12 if lbl_above else -0.15
        ax.text((x1+x2)/2, y+dy, lbl, ha='center', va='center',
                fontsize=7, color='#333', zorder=5)

def varrow(ax, x, y1, y2, col='#1A5276', lw=1.5, lbl='', lbl_right=True):
    ax.annotate('', xy=(x, y2), xytext=(x, y1),
                arrowprops=dict(arrowstyle='->', color=col, lw=lw,
                                mutation_scale=12), zorder=4)
    if lbl:
        dx = 0.15 if lbl_right else -0.15
        ax.text(x+dx, (y1+y2)/2, lbl, ha='left' if lbl_right else 'right',
                va='center', fontsize=7, color='#333', zorder=5)

def hline(ax, x1, x2, y, col='#E74C3C', lw=1.5, ls='--'):
    ax.plot([x1, x2], [y, y], color=col, lw=lw, ls=ls, zorder=3)

def vline(ax, x, y1, y2, col='#E74C3C', lw=1.5, ls='--'):
    ax.plot([x, x], [y1, y2], color=col, lw=lw, ls=ls, zorder=3)


# ═══════════════════════════════════════════════════════════════════════════════
#  DIAGRAM 1 — System Block Diagram  (clean horizontal layout)
# ═══════════════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(18, 10))
ax.set_xlim(0, 18); ax.set_ylim(0, 10)
ax.axis('off')
fig.patch.set_facecolor('white')

ax.text(9, 9.65, 'ShuffleNet V2 FPGA Accelerator — System Block Diagram',
        ha='center', fontsize=14, fontweight='bold')
ax.text(9, 9.28, 'iWave ZU19EG Dev Kit  (xczu19eg-ffvc1760-1-i)  |  100 MHz',
        ha='center', fontsize=10, color='#555')

# ────────────────────────────────────────────────────────────────────────────
# COLUMN 1 — Processing System
# ────────────────────────────────────────────────────────────────────────────
ps_x, ps_y, ps_w, ps_h = 0.3, 1.0, 3.4, 8.0
p = FancyBboxPatch((ps_x, ps_y), ps_w, ps_h, boxstyle='round,pad=0.05',
                   facecolor='#D5F5E3', edgecolor='#1E8449', linewidth=2.5, zorder=1)
ax.add_patch(p)
ax.text(ps_x+ps_w/2, ps_y+ps_h-0.35, 'Processing System (PS)',
        ha='center', fontsize=11, fontweight='bold', color='#1E8449')
ax.text(ps_x+ps_w/2, ps_y+ps_h-0.75, 'ARM Cortex-A53  @  1.2 GHz',
        ha='center', fontsize=9, color='#1E8449')

box(ax, 0.6, 7.2, 2.8, 0.9, 'AXI Master (HPM0 FPD)', '32-bit  |  master port',
    fc='#A9DFBF', ec='#1E8449')
box(ax, 0.6, 6.0, 2.8, 0.9, 'PL Clock  (pl_clk0)', '100 MHz output to PL',
    fc='#A9DFBF', ec='#1E8449')
box(ax, 0.6, 4.8, 2.8, 0.9, 'PL Reset  (pl_resetn0)', 'active-low to PL',
    fc='#A9DFBF', ec='#1E8449')
box(ax, 0.6, 1.3, 2.8, 3.2, 'DDR4  /  MIO  /  UART\nEthernet  /  I2C',
    'iWave ZU19EG board presets',
    fc='#A9DFBF', ec='#1E8449')

# ────────────────────────────────────────────────────────────────────────────
# COLUMN 2 — PL Wrapper (MMCM + AXI Slave + SmartConnect)
# ────────────────────────────────────────────────────────────────────────────
pl_x = 4.3
p2 = FancyBboxPatch((pl_x, 1.0), 5.0, 8.0, boxstyle='round,pad=0.05',
                    facecolor='#EBF5FB', edgecolor='#1A5276', linewidth=2.5, zorder=1)
ax.add_patch(p2)
ax.text(pl_x+2.5, 8.85, 'PL Fabric  —  shufflenet_board_top',
        ha='center', fontsize=11, fontweight='bold', color='#1A5276')

box(ax, pl_x+0.3, 7.2, 4.4, 1.0, 'AXI SmartConnect',
    'PS AXI master → accelerator slave',
    fc='#D6EAF8', ec='#2471A3', tfs=10)

box(ax, pl_x+0.3, 5.8, 4.4, 1.1, 'MMCM',
    'pl_clk0 (100 MHz) → clk_100m\n4-stage reset synchronizer',
    fc='#D6EAF8', ec='#1A5276', tfs=10)

box(ax, pl_x+0.3, 4.2, 4.4, 1.3, 'AXI4-Lite Slave',
    '0xA000_0000  (32 MB)\nAddr[21]=0: pixel write  |  Addr[21]=1: CSR',
    fc='#D6EAF8', ec='#1A5276', tfs=10)

box(ax, pl_x+0.3, 1.3, 4.4, 2.5,
    'accelerator_ctrl  (5-state FSM)',
    'IDLE → G1 → G1+G2\n→ G1+G2+G3 → G1+G3\nPipelined group execution',
    fc='#EAECEE', ec='#626567', tfs=9.5)

# arrows PS → PL wrapper
harrow(ax, 3.4, pl_x, 7.65, lbl='AXI4-Lite')
harrow(ax, 3.4, pl_x, 6.35, lbl='pl_clk0')
harrow(ax, 3.4, pl_x, 5.25, lbl='pl_resetn0')

# ────────────────────────────────────────────────────────────────────────────
# COLUMN 3 — accelerator_top (three groups)
# ────────────────────────────────────────────────────────────────────────────
ac_x = 10.0
p3 = FancyBboxPatch((ac_x, 1.0), 7.7, 8.0, boxstyle='round,pad=0.05',
                    facecolor='#FFFDE7', edgecolor='#B7950B', linewidth=2.5, zorder=1)
ax.add_patch(p3)
ax.text(ac_x+3.85, 8.85, 'accelerator_top',
        ha='center', fontsize=11, fontweight='bold', color='#7D6608')

box(ax, ac_x+0.3, 6.8, 7.1, 1.4, 'GROUP 1  —  3×3 Convolution + 3×3 MaxPool',
    '216 DSPs  |  114 BRAMs  |  14 K LUTs',
    fc='#FDEBD0', ec='#E67E22', lw=2, tfs=11, bold=True)

box(ax, ac_x+0.3, 5.0, 7.1, 1.5, 'GROUP 2  —  16 Shuffle Blocks  (DW + PW Conv)',
    '1218 DSPs  |  85 BRAMs  |  53 K LUTs',
    fc='#D6EAF8', ec='#1A5276', lw=2, tfs=11, bold=True)

box(ax, ac_x+0.3, 3.6, 7.1, 1.1, 'extra_mem BRAM',
    '29 channels × 1024 words × 12-bit  (Group 2 → Group 3 feature buffer)',
    fc='#F9EBEA', ec='#CB4335', lw=2, tfs=10)

box(ax, ac_x+0.3, 1.3, 7.1, 2.0, 'GROUP 3  —  PW Conv + AvgPool + FC + Argmax',
    '464 DSPs  |  379 BRAMs  |  12 K LUTs',
    fc='#F4ECF7', ec='#6C3483', lw=2, tfs=11, bold=True)

# arrows within accelerator
varrow(ax, ac_x+3.85, 6.8, 6.5, col='#E67E22', lbl='56×56×24')
varrow(ax, ac_x+3.85, 5.0, 4.7, col='#CB4335', lbl='PW results')
varrow(ax, ac_x+3.85, 3.6, 3.3, col='#6C3483', lbl='29 ch')

# class_idx output
harrow(ax, ac_x+7.4, ac_x+7.9, 2.3)
ax.text(ac_x+8.0, 2.3, 'class_idx\n[9:0]', fontsize=10, fontweight='bold',
        color='#6C3483', va='center')

# arrows PL wrapper → accelerator
harrow(ax, pl_x+4.7, ac_x, 7.5, lbl='image data')
harrow(ax, pl_x+4.7, ac_x, 6.4, lbl='100 MHz clk')
harrow(ax, pl_x+4.7, ac_x, 5.5, lbl='start pulse')
harrow(ax, ac_x, pl_x+4.7, 2.5, lbl='class_idx / done', col='#6C3483')

# ── Legend ────────────────────────────────────────────────────────────────────
items = [
    mpatches.Patch(fc='#D5F5E3', ec='#1E8449', label='Processing System (PS)'),
    mpatches.Patch(fc='#D6EAF8', ec='#1A5276', label='PL Board Wrapper (shufflenet_board_top)'),
    mpatches.Patch(fc='#FDEBD0', ec='#E67E22', label='Group 1  —  Conv3×3 + MaxPool'),
    mpatches.Patch(fc='#D6EAF8', ec='#1A5276', label='Group 2  —  DW + PW Conv'),
    mpatches.Patch(fc='#F9EBEA', ec='#CB4335', label='On-chip BRAM buffers'),
    mpatches.Patch(fc='#F4ECF7', ec='#6C3483', label='Group 3  —  FC + Argmax'),
]
ax.legend(handles=items, loc='lower left', fontsize=8.5,
          framealpha=0.95, ncol=2, bbox_to_anchor=(0.01, 0.01))

plt.savefig('system_diagram.png', dpi=150, bbox_inches='tight', facecolor='white')
plt.close()
print("Saved: system_diagram.png")


# ═══════════════════════════════════════════════════════════════════════════════
#  DIAGRAM 2 — Accelerator Dataflow (top-to-bottom, clean)
# ═══════════════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(18, 15))
ax.set_xlim(0, 18); ax.set_ylim(0, 15)
ax.axis('off')
fig.patch.set_facecolor('white')

ax.text(9, 14.6, 'ShuffleNet V2 FPGA Accelerator — Internal Architecture & Dataflow',
        ha='center', fontsize=13, fontweight='bold')
ax.text(9, 14.2, 'Q6.8 Fixed-Point Datapath  |  100 MHz  |  xczu19eg-ffvc1760-1-i',
        ha='center', fontsize=9.5, color='#555')

# ─── layout constants ────────────────────────────────────────────────────────
FX, FW = 0.3, 17.4          # frame x, width
IX, IW = 0.8, 16.4          # inner x start, usable inner width
BH = 1.1                    # block height
CX = 9.0                    # centre x for inter-frame arrows

# ── PS block ─────────────────────────────────────────────────────────────────
box(ax, 5.5, 13.0, 7.0, 0.9, 'ARM Cortex-A53  (Processing System)',
    'AXI4-Lite pixel write  →  photo_mem  (224×224×3)',
    fc='#D5F5E3', ec='#1E8449', lw=2, tfs=10, bold=True)
varrow(ax, CX, 13.0, 12.5, lbl='AXI4-Lite')   # PS → G1 top

# ══════════════════════════════════════════════════════════════════════════════
#  GROUP 1  (frame top = 12.5, bottom = 10.0  →  h = 2.5)
# ══════════════════════════════════════════════════════════════════════════════
G1_BOT, G1_TOP = 10.0, 12.5
p = FancyBboxPatch((FX, G1_BOT), FW, G1_TOP-G1_BOT,
                   boxstyle='round,pad=0.04', facecolor='#FEF5E7',
                   edgecolor='#E67E22', linewidth=2.5, zorder=1)
ax.add_patch(p)
# title INSIDE frame, 0.45 below top border
ax.text(CX, G1_TOP-0.38, 'GROUP 1  —  3×3 Convolution  +  3×3 MaxPool',
        ha='center', fontsize=11, fontweight='bold', color='#784212', zorder=3)
ax.text(CX, G1_TOP-0.72, '216 DSPs   |   114 BRAMs   |   14 K LUTs',
        ha='center', fontsize=8.5, color='#784212', zorder=3)

# 5 blocks evenly filling inner width — block y centres at G1_BY
G1_BY = G1_BOT + 0.25
# widths: [2.3, 2.5, 3.2, 2.5, 2.5] = 13.0  →  gaps = (16.4-13.0)/4 = 0.85
_x = IX
_w = [2.3, 2.5, 3.2, 2.5, 2.5]; _gap = (IW - sum(_w)) / (len(_w)-1)
g1_blk = []
for i,w in enumerate(_w):
    g1_blk.append((_x, w))
    _x += w + _gap

g1_labels = [
    ('photo_mem',    'Ping-pong BRAM\n224×224×3  |  Q6.8', '#F9EBEA', '#CB4335'),
    ('fifo_3×3',     '3-row sliding window\nFIFO per channel',  '#FDEBD0', '#E67E22'),
    ('conv3×3_core', '24 filters × 9 MACs\n3-cycle accumulation','#FDEBD0', '#E67E22'),
    ('maxpool_core', '3×3 max-of-9\n24 ch parallel',            '#FDEBD0', '#E67E22'),
    ('maxpool_mem',  'BRAM  56×56×24\n10-bit Q6.8',             '#F9EBEA', '#CB4335'),
]
for i,((bx,bw),(lbl,sub,fc,ec)) in enumerate(zip(g1_blk, g1_labels)):
    box(ax, bx, G1_BY, bw, BH, lbl, sub, fc=fc, ec=ec)
    if i < len(g1_blk)-1:
        harrow(ax, bx+bw, g1_blk[i+1][0], G1_BY+BH/2)

varrow(ax, CX, G1_BOT, G1_BOT-0.5, lbl='56×56×24  (Q6.8)')

# ══════════════════════════════════════════════════════════════════════════════
#  GROUP 2  (frame top = G1_BOT-0.5, bottom = G2_BOT  →  h = 3.3)
# ══════════════════════════════════════════════════════════════════════════════
G2_TOP = G1_BOT - 0.5
G2_BOT = G2_TOP - 3.3
p = FancyBboxPatch((FX, G2_BOT), FW, G2_TOP-G2_BOT,
                   boxstyle='round,pad=0.04', facecolor='#EAF2FF',
                   edgecolor='#1A5276', linewidth=2.5, zorder=1)
ax.add_patch(p)
ax.text(CX, G2_TOP-0.38, 'GROUP 2  —  16 Shuffle Blocks  (Depthwise 3×3  +  Pointwise 1×1)',
        ha='center', fontsize=11, fontweight='bold', color='#154360', zorder=3)
ax.text(CX, G2_TOP-0.72, '1218 DSPs   |   85 BRAMs   |   53 K LUTs   |   16 loop iterations',
        ha='center', fontsize=8.5, color='#154360', zorder=3)

# Single row of 5 blocks filling inner width
# widths: [2.2, 3.0, 3.2, 3.0, 2.2] = 13.6  →  gaps = (16.4-13.6)/4 = 0.7
G2_BY = G2_BOT + 0.7
_x = IX
_w2 = [2.2, 3.0, 3.2, 3.0, 2.2]; _gap2 = (IW - sum(_w2)) / (len(_w2)-1)
g2_blk = []
for w in _w2:
    g2_blk.append((_x, w))
    _x += w + _gap2

g2_labels = [
    ('group2_fifo',      '58 FIFOs (1 per ch)\nvariable width',        '#D6EAF8', '#1A5276'),
    ('dw_conv3×3_core',  '58 ch × 9 MACs\n522 DSPs parallel',          '#D6EAF8', '#1A5276'),
    ('DW result buffer', '58 ch × 784 words\nDist. RAM  (comb. read)', '#D5EEF7', '#1A5276'),
    ('conv1×1_core',     '12-parallel PW conv\n16 loops  (696 DSPs)',  '#D6EAF8', '#1A5276'),
    ('conv1×1_ctrl',     'Accumulation FSM\nwrite-enable timing',       '#D6EAF8', '#1A5276'),
]
for i,((bx,bw),(lbl,sub,fc,ec)) in enumerate(zip(g2_blk, g2_labels)):
    box(ax, bx, G2_BY, bw, BH, lbl, sub, fc=fc, ec=ec)
    if i < len(g2_blk)-1:
        harrow(ax, bx+bw, g2_blk[i+1][0], G2_BY+BH/2)

ax.text(CX, G2_BY+BH+0.22,
        'DW phase: FIFO → DW conv → stores results in buffer  |  '
        'PW phase: reads buffer → accumulate 12 ch × 16 iters → write extra_mem',
        ha='center', fontsize=7.5, color='#154360', zorder=3)

varrow(ax, CX, G2_BOT, G2_BOT-0.5, lbl='PW results  (29 ch)')

# ── extra_mem  (standalone BRAM between G2 and G3) ──────────────────────────
EM_TOP = G2_BOT - 0.5
EM_BOT = EM_TOP - 1.0
box(ax, 3.5, EM_BOT, 11.0, 1.0, 'extra_mem  (BRAM)',
    '29 channels  ×  1024 words  ×  12-bit  —  Group 2 → Group 3 feature map buffer',
    fc='#F9EBEA', ec='#CB4335', lw=2, tfs=10)
varrow(ax, CX, EM_BOT, EM_BOT-0.5, lbl='29 ch  (Q6.8)')

# ══════════════════════════════════════════════════════════════════════════════
#  GROUP 3  (frame top = EM_BOT-0.5)
# ══════════════════════════════════════════════════════════════════════════════
G3_TOP = EM_BOT - 0.5
G3_BOT = 0.3
p = FancyBboxPatch((FX, G3_BOT), FW, G3_TOP-G3_BOT,
                   boxstyle='round,pad=0.04', facecolor='#F4ECF7',
                   edgecolor='#6C3483', linewidth=2.5, zorder=1)
ax.add_patch(p)
ax.text(CX, G3_TOP-0.38, 'GROUP 3  —  PW Conv1×1  +  Global AvgPool  +  FC  +  Argmax',
        ha='center', fontsize=11, fontweight='bold', color='#4A235A', zorder=3)
ax.text(CX, G3_TOP-0.72, '464 DSPs   |   379 BRAMs   |   12 K LUTs',
        ha='center', fontsize=8.5, color='#4A235A', zorder=3)

# 5 blocks evenly filling inner width
# widths: [2.5, 2.5, 2.5, 2.5, 2.0] = 12.0  →  gaps = (16.4-12.0)/4 = 1.1
G3_BY = G3_BOT + 0.6
_x = IX
_w3 = [2.5, 2.5, 2.5, 2.5, 2.0]; _gap3 = (IW - sum(_w3)) / (len(_w3)-1)
g3_blk = []
for w in _w3:
    g3_blk.append((_x, w))
    _x += w + _gap3

g3_labels = [
    ('conv1×1_g3_core', '16-parallel PW\n64 filter groups',    '#E8DAEF', '#6C3483'),
    ('avg_pool_core',   '16 channels\n49 pixels each',          '#E8DAEF', '#6C3483'),
    ('register file',   '1024 × 9-bit\navgpool results',        '#D7BDE2', '#6C3483'),
    ('fc_core',         '32-parallel MACs\n1000 output classes','#E8DAEF', '#6C3483'),
    ('argmax',          'Running max\nclass_idx [9:0]',         '#E8DAEF', '#6C3483'),
]
for i,((bx,bw),(lbl,sub,fc,ec)) in enumerate(zip(g3_blk, g3_labels)):
    box(ax, bx, G3_BY, bw, BH, lbl, sub, fc=fc, ec=ec)
    if i < len(g3_blk)-1:
        harrow(ax, bx+bw, g3_blk[i+1][0], G3_BY+BH/2)

# class_idx output arrow
harrow(ax, g3_blk[-1][0]+g3_blk[-1][1], g3_blk[-1][0]+g3_blk[-1][1]+0.4, G3_BY+BH/2)
ax.text(g3_blk[-1][0]+g3_blk[-1][1]+0.5, G3_BY+BH/2,
        'class_idx\n[9:0]', fontsize=10, fontweight='bold',
        color='#4A235A', va='center')

# accelerator_ctrl annotation
box(ax, 5.5, G3_BOT+0.08, 7.0, 0.42,
    'accelerator_ctrl  —  5-state pipelined FSM:  IDLE → G1 → G1+G2 → G1+G2+G3 → G1+G3',
    fc='#EAECEE', ec='#626567', tfs=8)

# ── Legend ────────────────────────────────────────────────────────────────────
items = [
    mpatches.Patch(fc='#D5F5E3', ec='#1E8449', label='Processing System (PS)'),
    mpatches.Patch(fc='#FDEBD0', ec='#E67E22', label='Group 1 modules'),
    mpatches.Patch(fc='#D6EAF8', ec='#1A5276', label='Group 2 modules'),
    mpatches.Patch(fc='#D5EEF7', ec='#1A5276', label='DW result buffer (Dist. RAM)'),
    mpatches.Patch(fc='#F9EBEA', ec='#CB4335', label='BRAM buffers (photo / maxpool / extra)'),
    mpatches.Patch(fc='#E8DAEF', ec='#6C3483', label='Group 3 modules'),
]
ax.legend(handles=items, loc='lower right', fontsize=8.5,
          framealpha=0.95, ncol=2, bbox_to_anchor=(0.99, 0.01))

plt.savefig('accelerator_diagram.png', dpi=150, bbox_inches='tight', facecolor='white')
plt.close()
print("Saved: accelerator_diagram.png")
