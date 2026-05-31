"""
Generate block diagrams for ShuffleNet V2 FPGA Accelerator.
"""
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch

def box(ax, x, y, w, h, label, sub='',
        fc='#D6EAF8', ec='#1A5276', lw=1.5, fs=9, sfs=7.5, bold=False):
    rect = FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.02',
                          facecolor=fc, edgecolor=ec, linewidth=lw, zorder=2)
    ax.add_patch(rect)
    weight = 'bold' if bold else 'normal'
    cy = y + h/2 + (0.1 if sub else 0)
    ax.text(x+w/2, cy, label, ha='center', va='center',
            fontsize=fs, fontweight=weight, zorder=3, multialignment='center')
    if sub:
        ax.text(x+w/2, y+h/2-0.12, sub, ha='center', va='center',
                fontsize=sfs, color='#555', zorder=3, multialignment='center')

def arr(ax, x1, y1, x2, y2, lbl='', lw=1.5, col='#1A5276', fs=7.5):
    ax.annotate('', xy=(x2,y2), xytext=(x1,y1),
                arrowprops=dict(arrowstyle='->', color=col, lw=lw,
                                mutation_scale=13), zorder=4)
    if lbl:
        mx,my = (x1+x2)/2, (y1+y2)/2
        ax.text(mx+0.05, my, lbl, fontsize=fs, color='#333',
                ha='left', va='center', zorder=5)

# ═══════════════════════════════════════════════════════════════════
#  DIAGRAM 1 — System Block Diagram
# ═══════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(15, 8))
ax.set_xlim(0, 15); ax.set_ylim(0, 8)
ax.axis('off')
fig.patch.set_facecolor('white')
ax.set_title('ShuffleNet V2 FPGA Accelerator — System Block Diagram\n'
             'iWave ZU19EG Dev Kit  |  xczu19eg-ffvc1760-1-i  |  100 MHz',
             fontsize=11, fontweight='bold', pad=8)

# ── PS ──────────────────────────────────────────────────────────────
box(ax,0.2,2.5,2.8,4.5,'Processing System (PS)',
    'ARM Cortex-A53 @ 1.2 GHz',
    fc='#D5F5E3', ec='#1E8449', lw=2, fs=10, bold=True)
box(ax,0.4,5.4,2.4,0.9,'AXI Master\nHPM0 FPD\n(32-bit)',
    fc='#A9DFBF',ec='#1E8449',fs=8)
box(ax,0.4,4.5,2.4,0.7,'pl_clk0  100 MHz',
    fc='#A9DFBF',ec='#1E8449',fs=8)
box(ax,0.4,3.6,2.4,0.7,'pl_resetn0',
    fc='#A9DFBF',ec='#1E8449',fs=8)
box(ax,0.4,2.7,2.4,0.7,'DDR4 / MIO / UART\n(iWave presets)',
    fc='#A9DFBF',ec='#1E8449',fs=7.5)

# ── SmartConnect ─────────────────────────────────────────────────────
box(ax,3.4,5.2,1.5,1.2,'AXI\nSmart\nConnect',fc='#EBF5FB',ec='#2471A3',fs=8)
arr(ax,2.8,5.85,3.4,5.85, lbl='AXI4-Lite')

# ── PL outer frame ────────────────────────────────────────────────────
box(ax,5.0,0.4,9.8,7.0,'',fc='#EBF5FB',ec='#1A5276',lw=2.5)
ax.text(9.9,7.15,'PL Fabric  —  shufflenet_board_top',
        ha='center',va='bottom',fontsize=10,fontweight='bold',color='#1A5276')

# ── MMCM + Reset ─────────────────────────────────────────────────────
box(ax,5.2,5.8,2.2,1.1,'MMCM',
    'pl_clk0 → 100 MHz\n4-stage reset sync',
    fc='#D6EAF8',ec='#1A5276',fs=8.5)
arr(ax,4.9,4.85,5.2,6.35)    # pl_clk0 → MMCM
arr(ax,2.8,3.95,5.0,3.95)    # pl_resetn0 crossing

# clock distribution
ax.annotate('',xy=(7.6,6.35),xytext=(7.4,6.35),
            arrowprops=dict(arrowstyle='-',color='#E74C3C',lw=1.5,
                            linestyle='dashed'))
ax.plot([7.4,7.4],[6.35,4.3],color='#E74C3C',lw=1.5,ls='--',zorder=3)
ax.annotate('',xy=(7.4,4.3),xytext=(7.4,4.3),
            arrowprops=dict(arrowstyle='->',color='#E74C3C',lw=1.5))
ax.text(7.45,5.4,'100 MHz\nclk domain',fontsize=7,color='#E74C3C',ha='left')

# ── AXI Slave ────────────────────────────────────────────────────────
box(ax,5.2,3.8,2.2,1.4,'AXI4-Lite\nSlave',
    '0xA0000000  32 MB\nPixel write + CSR\nphoto_ready / class_idx',
    fc='#D6EAF8',ec='#1A5276',fs=8)
arr(ax,4.9,5.8,5.2,5.2)
arr(ax,4.9,4.5,5.2,4.5)

# ── accelerator_top ───────────────────────────────────────────────────
box(ax,7.6,0.7,6.9,6.0,'',fc='#FEF9E7',ec='#B7950B',lw=2)
ax.text(11.05,6.5,'accelerator_top  +  accelerator_ctrl FSM',
        ha='center',va='bottom',fontsize=9,fontweight='bold',color='#7D6608')

arr(ax,7.4,4.5,7.6,4.5, lbl='start\nclass_idx')

# groups
box(ax,7.8,5.2,6.5,1.1,'GROUP 1',
    'photo_mem (BRAM)  →  fifo_3×3  →  conv3×3_core (24 filters)  →  maxpool  →  maxpool_mem (BRAM)\n'
    '216 DSPs   114 BRAMs   14K LUTs',
    fc='#FDEBD0',ec='#E67E22',lw=1.5,fs=8.5,bold=True)

box(ax,7.8,3.7,6.5,1.2,'GROUP 2  —  16 Shuffle Blocks',
    'group2_fifo (58ch)  →  dw_conv3×3_core (58 filters)  →  DW buffer (dist. RAM)  →  conv1×1_core (12 parallel)\n'
    '1218 DSPs   85 BRAMs   53K LUTs',
    fc='#D6EAF8',ec='#1A5276',lw=1.5,fs=8.5,bold=True)

box(ax,7.8,2.5,6.5,0.9,'extra_mem BRAM',
    '29 channels  ×  1024 words  ×  12-bit  (Group 2 → Group 3 feature map buffer)',
    fc='#F9EBEA',ec='#CB4335',lw=1.5,fs=8.5,bold=True)

box(ax,7.8,1.0,6.5,1.2,'GROUP 3',
    'conv1×1_g3 (16 parallel)  →  avg_pool  →  register file (1024)  →  fc_core (32 par.)  →  argmax\n'
    '464 DSPs   379 BRAMs   12K LUTs',
    fc='#F4ECF7',ec='#6C3483',lw=1.5,fs=8.5,bold=True)

arr(ax,11.05,5.2,11.05,4.9,col='#E67E22')
arr(ax,11.05,3.7,11.05,3.4,col='#CB4335')
arr(ax,11.05,2.5,11.05,2.2,col='#6C3483')

# class_idx output
arr(ax,14.3,1.55,14.8,1.55)
ax.text(14.82,1.55,'class_idx',fontsize=8,fontweight='bold',
        color='#6C3483',va='center')

# Legend
leg = [mpatches.Patch(fc='#D5F5E3',ec='#1E8449',label='Processing System (PS)'),
       mpatches.Patch(fc='#D6EAF8',ec='#1A5276',label='PL Board Wrapper + AXI'),
       mpatches.Patch(fc='#FDEBD0',ec='#E67E22',label='Group 1 (conv+maxpool)'),
       mpatches.Patch(fc='#D6EAF8',ec='#1A5276',label='Group 2 (DW+PW conv)'),
       mpatches.Patch(fc='#F9EBEA',ec='#CB4335',label='On-chip BRAM buffers'),
       mpatches.Patch(fc='#F4ECF7',ec='#6C3483',label='Group 3 (PW+pool+FC)')]
ax.legend(handles=leg,loc='lower left',fontsize=7.5,framealpha=0.95,ncol=2)

plt.tight_layout()
plt.savefig('system_diagram.png',dpi=150,bbox_inches='tight',facecolor='white')
plt.close()
print("Saved: system_diagram.png")


# ═══════════════════════════════════════════════════════════════════
#  DIAGRAM 2 — Accelerator Dataflow (top-to-bottom pipeline)
# ═══════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(14, 11))
ax.set_xlim(0,14); ax.set_ylim(0,11)
ax.axis('off')
fig.patch.set_facecolor('white')
ax.set_title('ShuffleNet V2 FPGA Accelerator — Internal Architecture & Dataflow\n'
             '100 MHz  |  Q6.8 Fixed-Point Datapath',
             fontsize=11, fontweight='bold', pad=8)

BW=1.7; BH=0.65   # standard box dims
CX=7.0             # centre x for data-flow column
LX=0.3             # left annotation x
RX=11.2            # right annotation x

# ── Input image ──────────────────────────────────────────────────────
box(ax,3.5,9.9,3.0,0.7,'PS ARM Cortex-A53',
    fc='#D5F5E3',ec='#1E8449',fs=9,bold=True)
arr(ax,5.0,9.9,5.0,9.35,lbl='AXI4-Lite  pixel write')
box(ax,3.5,8.6,3.0,0.75,'photo_mem\n(ping-pong BRAM)',
    fc='#F9EBEA',ec='#CB4335',fs=8.5)
ax.text(LX,8.95,'224×224×3\n15-bit Q6.8',fontsize=8,ha='left',color='#555')

# ── GROUP 1 frame ────────────────────────────────────────────────────
box(ax,0.2,6.6,13.6,1.85,'',fc='#FEF5E7',ec='#E67E22',lw=2)
ax.text(7.0,8.3,'GROUP 1  —  3×3 Convolution + 3×3 MaxPool',
        ha='center',va='bottom',fontsize=9.5,fontweight='bold',color='#784212')
ax.text(LX,6.65,'216 DSPs\n114 BRAMs\n14K LUTs',fontsize=7.5,va='bottom',color='#784212')

arr(ax,5.0,8.6,5.0,8.45)
# Group 1 internal
bx=1.5
box(ax,bx,6.85,BW,BH,'fifo_3×3\n3-row sliding win',fc='#FDEBD0',ec='#E67E22',fs=8)
arr(ax,bx+BW,6.85+BH/2, bx+BW+0.4,6.85+BH/2)
box(ax,bx+BW+0.4,6.85,2.1,BH,'conv3×3_core\n24 filters × 9 MACs\n(24 parallel DSPs)',fc='#FDEBD0',ec='#E67E22',fs=8)
arr(ax,bx+BW+0.4+2.1,6.85+BH/2, bx+BW+0.4+2.1+0.4,6.85+BH/2)
box(ax,bx+BW+0.4+2.1+0.4,6.85,BW,BH,'maxpool_core\n3×3 max-of-9\n(24 ch parallel)',fc='#FDEBD0',ec='#E67E22',fs=8)
arr(ax,bx+BW+0.4+2.1+0.4+BW,6.85+BH/2, bx+BW+0.4+2.1+0.4+BW+0.4,6.85+BH/2)
box(ax,bx+BW+0.4+2.1+0.4+BW+0.4,6.85,2.0,BH,'maxpool_mem\nBRAM 56×56×24\n10-bit Q6.8',fc='#F9EBEA',ec='#CB4335',fs=8)
ax.text(RX,7.2,'3 cycles\naccum.',fontsize=7.5,color='#784212',ha='left')
arr(ax,5.0,6.6,5.0,6.45,lbl='56×56×24')

# ── GROUP 2 frame ────────────────────────────────────────────────────
box(ax,0.2,3.7,13.6,2.7,'',fc='#EAF2FF',ec='#1A5276',lw=2)
ax.text(7.0,6.3,'GROUP 2  —  16 Shuffle Blocks  (DW 3×3  →  1×1 PW)',
        ha='center',va='bottom',fontsize=9.5,fontweight='bold',color='#154360')
ax.text(LX,3.75,'1218 DSPs\n85 BRAMs\n53K LUTs\n16 loops',fontsize=7.5,va='bottom',color='#154360')

# DW row
bx2=1.5; ry=5.25
box(ax,bx2,ry,BW,BH,'group2_fifo\n58 per ch\nvar. width',fc='#D6EAF8',ec='#1A5276',fs=8)
arr(ax,bx2+BW,ry+BH/2,bx2+BW+0.35,ry+BH/2)
box(ax,bx2+BW+0.35,ry,2.1,BH,'dw_conv3×3_core\n58 ch × 9 MACs\n(522 DSPs)',fc='#D6EAF8',ec='#1A5276',fs=8)
arr(ax,bx2+BW+0.35+2.1,ry+BH/2,bx2+BW+0.35+2.1+0.35,ry+BH/2)
box(ax,bx2+BW+0.35+2.1+0.35,ry,2.2,BH,'DW result buffer\n58×784 dist. RAM\n(comb. read)',fc='#D5EEF7',ec='#1A5276',fs=8)
ax.text(RX,ry+BH/2,'DW: 1 output\nper cycle',fontsize=7.5,color='#154360',va='center',ha='left')
ax.text(bx2+BW+0.35+2.1+0.35+1.1,ry-0.25,'↓ after DW phase',fontsize=7.5,color='#154360',ha='center')

# PW row
ry2=3.9
box(ax,bx2,ry2,2.1,BH,'conv1×1_core\n12-parallel PW\n(696 DSPs)',fc='#D6EAF8',ec='#1A5276',fs=8)
arr(ax,bx2-0.1,ry2+BH/2,bx2-0.1,ry+BH/2+0.02,col='#154360')   # down from buffer area
ax.text(RX,ry2+BH/2,'16 loop\niters × 12 ch',fontsize=7.5,color='#154360',va='center',ha='left')
arr(ax,bx2+2.1,ry2+BH/2,bx2+2.1+0.4,ry2+BH/2)
box(ax,bx2+2.5,ry2,2.1,BH,'conv1×1_ctrl\nN_ACC steps\nwrite enable',fc='#D6EAF8',ec='#1A5276',fs=8)
arr(ax,bx2+2.5+2.1,ry2+BH/2,bx2+2.5+2.1+0.4,ry2+BH/2)
box(ax,bx2+5.0,ry2,2.1,BH,'extra_mem\nBRAM 29ch×1024\n12-bit Q6.8',fc='#F9EBEA',ec='#CB4335',fs=8)

arr(ax,5.0,3.7,5.0,3.55,lbl='29ch × 1024')

# ── GROUP 3 frame ────────────────────────────────────────────────────
box(ax,0.2,0.7,13.6,2.75,'',fc='#F4ECF7',ec='#6C3483',lw=2)
ax.text(7.0,3.35,'GROUP 3  —  1×1 PW Conv  +  AvgPool  +  FC  +  Argmax',
        ha='center',va='bottom',fontsize=9.5,fontweight='bold',color='#4A235A')
ax.text(LX,0.75,'464 DSPs\n379 BRAMs\n12K LUTs',fontsize=7.5,va='bottom',color='#4A235A')

bx3=1.2; ry3=1.7
box(ax,bx3,ry3,2.0,BH,'conv1×1_g3_core\n16-parallel PW\n(464 DSPs)',fc='#E8DAEF',ec='#6C3483',fs=8)
arr(ax,bx3+2.0,ry3+BH/2,bx3+2.35,ry3+BH/2)
box(ax,bx3+2.35,ry3,1.8,BH,'avg_pool_core\n16 ch\n49 pixels',fc='#E8DAEF',ec='#6C3483',fs=8)
arr(ax,bx3+2.35+1.8,ry3+BH/2,bx3+2.35+2.15,ry3+BH/2)
box(ax,bx3+4.5,ry3,1.9,BH,'register file\n1024 × 9-bit\n(64 groups)',fc='#D7BDE2',ec='#6C3483',fs=8)
arr(ax,bx3+4.5+1.9,ry3+BH/2,bx3+4.5+2.25,ry3+BH/2)
box(ax,bx3+6.75,ry3,2.0,BH,'fc_core\n32-parallel\n1000 classes',fc='#E8DAEF',ec='#6C3483',fs=8)
arr(ax,bx3+6.75+2.0,ry3+BH/2,bx3+6.75+2.35,ry3+BH/2)
box(ax,bx3+9.1,ry3,1.8,BH,'argmax\nclassifier',fc='#E8DAEF',ec='#6C3483',fs=8)
arr(ax,bx3+9.1+1.8,ry3+BH/2,bx3+9.1+2.15,ry3+BH/2)
ax.text(13.2,ry3+BH/2,'class_idx\n[9:0]',fontsize=9,fontweight='bold',
        color='#4A235A',va='center',ha='left')

# accel ctrl
box(ax,5.0,0.85,3.8,0.65,'accelerator_ctrl  (5-state pipeline FSM)\n'
    'IDLE → G1 → G1+G2 → G1+G2+G3 → G1+G3',
    fc='#EAECEE',ec='#626567',fs=8)

# g3 weight roms annotation
ax.text(RX,2.1,'weight ROMs\n(BN-folded Q6.8\nhex → BRAM init)\n379 BRAMs total',
        fontsize=7.5,color='#CB4335',ha='left',va='center',
        bbox=dict(boxstyle='round',fc='#FDEDEC',ec='#CB4335',alpha=0.9))

plt.tight_layout()
plt.savefig('accelerator_diagram.png',dpi=150,bbox_inches='tight',facecolor='white')
plt.close()
print("Saved: accelerator_diagram.png")
