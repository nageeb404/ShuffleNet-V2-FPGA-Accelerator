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
#  DIAGRAM 2 — Accelerator Dataflow (top-to-bottom)
# ═══════════════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(18, 13))
ax.set_xlim(0, 18); ax.set_ylim(0, 13)
ax.axis('off')
fig.patch.set_facecolor('white')

ax.text(9, 12.6, 'ShuffleNet V2 FPGA Accelerator — Internal Architecture & Dataflow',
        ha='center', fontsize=13, fontweight='bold')
ax.text(9, 12.25, 'Q6.8 Fixed-Point Datapath  |  100 MHz  |  xczu19eg-ffvc1760-1-i',
        ha='center', fontsize=9, color='#555')

# ── PS input ────────────────────────────────────────────────────────────────
box(ax, 6.0, 11.3, 6.0, 0.85, 'ARM Cortex-A53 (PS)',
    'AXI4-Lite pixel write  →  photo_mem',
    fc='#D5F5E3', ec='#1E8449', lw=2, tfs=10, bold=True)
varrow(ax, 9.0, 11.3, 10.7)

# ── GROUP 1 ─────────────────────────────────────────────────────────────────
p = FancyBboxPatch((0.3, 8.5), 17.4, 2.05, boxstyle='round,pad=0.04',
                   facecolor='#FEF5E7', edgecolor='#E67E22', linewidth=2.5, zorder=1)
ax.add_patch(p)
ax.text(9.0, 10.42, 'GROUP 1  —  3×3 Convolution  +  3×3 MaxPool',
        ha='center', fontsize=11, fontweight='bold', color='#784212')
ax.text(0.5, 8.6, '216 DSPs\n114 BRAMs\n14 K LUTs', fontsize=8, va='bottom', color='#784212')

# G1 blocks
bx, by, bw, bh = 1.2, 9.0, 2.5, 1.0
box(ax, bx, by, bw, bh, 'photo_mem', 'Ping-pong BRAM\n224×224×3  |  Q6.8',
    fc='#F9EBEA', ec='#CB4335')
harrow(ax, bx+bw, bx+bw+0.5, by+bh/2, lbl='pixels')
box(ax, bx+bw+0.5, by, 2.5, bh, 'fifo_3×3', '3-row sliding window\nFIFO per channel',
    fc='#FDEBD0', ec='#E67E22')
harrow(ax, bx+bw+0.5+2.5, bx+bw+0.5+2.5+0.5, by+bh/2, lbl='3×3 window')
box(ax, bx+bw+0.5+2.5+0.5, by, 3.2, bh, 'conv3×3_core', '24 filters  ×  9 MACs\n3-cycle accumulation',
    fc='#FDEBD0', ec='#E67E22')
harrow(ax, bx+bw+0.5+2.5+0.5+3.2, bx+bw+0.5+2.5+0.5+3.2+0.5, by+bh/2, lbl='relu + quant')
box(ax, bx+bw+0.5+2.5+0.5+3.2+0.5, by, 2.5, bh, 'maxpool_core', '3×3 max-of-9\n24 ch parallel',
    fc='#FDEBD0', ec='#E67E22')
harrow(ax, bx+bw+0.5+2.5+0.5+3.2+0.5+2.5, bx+bw+0.5+2.5+0.5+3.2+0.5+2.5+0.5,
       by+bh/2, lbl='quantized')
box(ax, bx+bw+0.5+2.5+0.5+3.2+0.5+2.5+0.5, by, 2.5, bh, 'maxpool_mem',
    'BRAM  56×56×24\n10-bit Q6.8',
    fc='#F9EBEA', ec='#CB4335')

varrow(ax, 15.2, 8.5, 7.85, lbl='56×56×24  (Q6.8)')

# ── GROUP 2 ─────────────────────────────────────────────────────────────────
p = FancyBboxPatch((0.3, 4.8), 17.4, 2.85, boxstyle='round,pad=0.04',
                   facecolor='#EAF2FF', edgecolor='#1A5276', linewidth=2.5, zorder=1)
ax.add_patch(p)
ax.text(9.0, 7.52, 'GROUP 2  —  16 Shuffle Blocks  (Depthwise 3×3  +  Pointwise 1×1)',
        ha='center', fontsize=11, fontweight='bold', color='#154360')
ax.text(0.5, 4.9, '1218 DSPs\n85 BRAMs\n53 K LUTs\n16 loops', fontsize=8, va='bottom', color='#154360')

# DW row
bx2, by2 = 1.2, 6.35
box(ax, bx2, by2, 2.5, 1.0, 'group2_fifo', '58 FIFOs (1 per ch)\nvariable width',
    fc='#D6EAF8', ec='#1A5276')
harrow(ax, bx2+2.5, bx2+3.0, by2+0.5, lbl='3×3 windows')
box(ax, bx2+3.0, by2, 3.2, 1.0, 'dw_conv3×3_core', '58 channels\n9 MACs each  (522 DSPs)',
    fc='#D6EAF8', ec='#1A5276')
harrow(ax, bx2+6.2, bx2+6.7, by2+0.5, lbl='DW result')
box(ax, bx2+6.7, by2, 3.0, 1.0, 'DW result buffer', '58 ch × 784 words\nDistributed RAM (comb. read)',
    fc='#D5EEF7', ec='#1A5276')

ax.text(9.0, 6.15, '▼  after DW phase completes  ▼',
        ha='center', fontsize=8, color='#154360')

# PW row
by3 = 5.0
box(ax, bx2, by3, 3.2, 1.0, 'conv1×1_core', '12-parallel PW\n16 loop iters  (696 DSPs)',
    fc='#D6EAF8', ec='#1A5276')
harrow(ax, bx2+3.2, bx2+3.7, by3+0.5, lbl='N_ACC steps')
box(ax, bx2+3.7, by3, 2.8, 1.0, 'conv1×1_ctrl', 'Accumulation FSM\nwrite-enable timing',
    fc='#D6EAF8', ec='#1A5276')
harrow(ax, bx2+6.5, bx2+7.0, by3+0.5, lbl='PW result')
box(ax, bx2+7.0, by3, 3.0, 1.0, 'extra_mem BRAM',
    '29 ch × 1024 × 12-bit\nG2 → G3 feature buffer',
    fc='#F9EBEA', ec='#CB4335')

varrow(ax, 11.5, 4.8, 4.15, lbl='29 ch  (Q6.8)')

# ── GROUP 3 ─────────────────────────────────────────────────────────────────
p = FancyBboxPatch((0.3, 0.6), 17.4, 3.35, boxstyle='round,pad=0.04',
                   facecolor='#F4ECF7', edgecolor='#6C3483', linewidth=2.5, zorder=1)
ax.add_patch(p)
ax.text(9.0, 3.82, 'GROUP 3  —  PW Conv1×1  +  Global AvgPool  +  FC  +  Argmax',
        ha='center', fontsize=11, fontweight='bold', color='#4A235A')
ax.text(0.5, 0.7, '464 DSPs\n379 BRAMs\n12 K LUTs', fontsize=8, va='bottom', color='#4A235A')

bx3, by3b = 1.2, 2.3
bw3 = 2.6
gap = 0.4
box(ax, bx3,          by3b, bw3, 1.0, 'conv1×1_g3_core',
    '16-parallel PW\n64 filter groups', fc='#E8DAEF', ec='#6C3483')
harrow(ax, bx3+bw3, bx3+bw3+gap, by3b+0.5)
box(ax, bx3+bw3+gap, by3b, bw3, 1.0, 'avg_pool_core',
    '16 channels\n49 pixels each', fc='#E8DAEF', ec='#6C3483')
harrow(ax, bx3+2*(bw3+gap), bx3+2*(bw3+gap)+gap, by3b+0.5, lbl='1024 values')
box(ax, bx3+2*(bw3+gap)+gap, by3b, bw3, 1.0, 'register file',
    '1024 × 9-bit\n(avgpool results)', fc='#D7BDE2', ec='#6C3483')
harrow(ax, bx3+3*(bw3+gap)+gap, bx3+3*(bw3+gap)+2*gap, by3b+0.5)
box(ax, bx3+3*(bw3+gap)+2*gap, by3b, bw3, 1.0, 'fc_core',
    '32-parallel MACs\n1000 output classes', fc='#E8DAEF', ec='#6C3483')
harrow(ax, bx3+4*(bw3+gap)+2*gap, bx3+4*(bw3+gap)+3*gap, by3b+0.5)
box(ax, bx3+4*(bw3+gap)+3*gap, by3b, bw3, 1.0, 'argmax',
    'Running max\nclass_idx [9:0]', fc='#E8DAEF', ec='#6C3483')
harrow(ax, bx3+5*(bw3+gap)+3*gap, bx3+5*(bw3+gap)+3*gap+0.5, by3b+0.5)
ax.text(bx3+5*(bw3+gap)+3*gap+0.6, by3b+0.5,
        'class_idx\n[9:0]', fontsize=10, fontweight='bold',
        color='#4A235A', va='center')

# weight ROM annotation
box(ax, 1.2, 1.0, 4.0, 1.0, 'Weight ROMs (BRAM)',
    'BN-folded Q6.8 weights\nhex files → $readmemh init',
    fc='#FDEDEC', ec='#CB4335', tfs=9)
ax.annotate('', xy=(3.75, 2.3), xytext=(3.2, 2.0),
            arrowprops=dict(arrowstyle='->', color='#CB4335', lw=1.5,
                            mutation_scale=11), zorder=4)

# accel_ctrl
box(ax, 6.5, 1.0, 5.0, 1.0, 'accelerator_ctrl  (FSM)',
    'IDLE → G1 → G1+G2 → G1+G2+G3 → G1+G3\n5-state pipelined execution',
    fc='#EAECEE', ec='#626567', tfs=9)

# Legend
items = [
    mpatches.Patch(fc='#D5F5E3', ec='#1E8449', label='Processing System'),
    mpatches.Patch(fc='#FDEBD0', ec='#E67E22', label='Group 1 modules'),
    mpatches.Patch(fc='#D6EAF8', ec='#1A5276', label='Group 2 modules'),
    mpatches.Patch(fc='#E8DAEF', ec='#6C3483', label='Group 3 modules'),
    mpatches.Patch(fc='#F9EBEA', ec='#CB4335', label='BRAM buffers'),
    mpatches.Patch(fc='#D5EEF7', ec='#1A5276', label='Distributed RAM buffer'),
]
ax.legend(handles=items, loc='lower right', fontsize=8.5,
          framealpha=0.95, ncol=2)

plt.savefig('accelerator_diagram.png', dpi=150, bbox_inches='tight', facecolor='white')
plt.close()
print("Saved: accelerator_diagram.png")
