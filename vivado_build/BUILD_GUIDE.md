# Vivado Build Guide — PYNQ-Z2 Systolic Array with Selective PE Protection

## Overview

This guide walks through building the full PYNQ-Z2 bitstream from scratch using Vivado 2022.2. The build system is fully self-contained inside `vivado_build/` and does not modify any original source files.

---

## Folder Structure

```
vivado_build/
├── config/
│   └── design_config.tcl     ← ① EDIT THIS FIRST
├── tcl/
│   ├── run_all.tcl            ← ② Run this to build everything
│   ├── 01_gen_protected_rtl.tcl
│   ├── 02_create_project.tcl
│   ├── 03_create_bd.tcl
│   └── 04_synth_impl.tcl
├── rtl/
│   ├── pe_dmr.v               (DMR PE wrapper)
│   ├── pe_tmr.v               (TMR PE wrapper)
│   ├── mm_protected.sv        (Protected controller)
│   └── mm_protected_axi.v    (AXI wrapper)
├── generated/                 ← Auto-created: systolic_protected.sv
├── constraints/
│   └── pynq_z2.xdc
├── project/                   ← Auto-created: Vivado project
└── output/                    ← Auto-created: .bit + .hwh files
```

---

## Step 1 — Configure Your Design

Open **`vivado_build/config/design_config.tcl`** and set:

```tcl
set DESIGN_N 4        # Systolic array dimension (4×4 PEs). M = N is fixed.
set DESIGN_D_W 8      # Data width in bits (INT8).

set PE_PROTECTION_MAP {
    {0 0 TMR}   {0 1 TMR}   {0 2 DMR}   {0 3 DMR}
    {1 0 TMR}   {1 1 DMR}   {1 2 none}  {1 3 none}
    {2 0 DMR}   {2 1 none}  {2 2 none}  {2 3 none}
    {3 0 none}  {3 1 none}  {3 2 none}  {3 3 none}
}
```

**Protection mode guide:**

| Mode | Hardware | Overhead | Behavior |
|------|----------|----------|----------|
| `none` | Single PE | 1× | No fault tolerance |
| `DMR` | 2× PE + comparator | ~2× | Detects fault → `fault_detected` flag |
| `TMR` | 3× PE + majority voter | ~3× | Corrects single fault silently |

> **The choice is yours.** There is no fixed correct answer — it depends on your model's sensitivity (NVF analysis) and your FPGA resource budget.

---

## Step 2 — Set Up Vivado 2022.2

On your server/workstation, source the Vivado 2022.2 environment:

```bash
source /path/to/xilinx.vivado.2022.2.csh   # for csh/tcsh
# or for bash:
source /tools/Xilinx/Vivado/2022.2/settings64.sh
```

Verify:
```bash
which vivado
vivado -version
```

---

## Step 3 — Run the Full Build (Batch Mode — Recommended)

Navigate to the project root and run:

```bash
cd /Users/springbaby/Documents/Nguyen/PHD/EXP/DNN_verification/SystolicArray_FPGA_master_protection

vivado -mode batch -source vivado_build/tcl/run_all.tcl \
       -log vivado_build/output/vivado.log \
       -journal vivado_build/output/vivado.jou
```

This single command performs all steps automatically:
1. Reads `design_config.tcl`
2. Generates `vivado_build/generated/systolic_protected.sv`
3. Creates the Vivado project at `vivado_build/project/`
4. Builds the Block Design (Zynq PS7 + AXI DMA + mm_protected_axi + AXI GPIO)
5. Runs Synthesis → Implementation → Bitstream
6. Copies outputs to `vivado_build/output/`

**Expected runtime:** 20–40 minutes depending on N and server speed.

---

## Step 4 — Alternative: Step-by-Step in Vivado GUI

Open Vivado 2022.2 GUI, then in the Tcl Console:

```tcl
# Step 1 — load config
source vivado_build/config/design_config.tcl

# Step 2 — generate protected RTL
source vivado_build/tcl/01_gen_protected_rtl.tcl

# Step 3 — create project (check it opened correctly in GUI)
source vivado_build/tcl/02_create_project.tcl

# Step 4 — build block design (view in IP Integrator after this)
source vivado_build/tcl/03_create_bd.tcl

# Step 5 — synthesize + implement + bitstream
source vivado_build/tcl/04_synth_impl.tcl
```

---

## Step 5 — Deploy to PYNQ-Z2 Board

After a successful build, the `output/` folder contains:
- `pynq_z2_system.bit` — FPGA bitstream
- `pynq_z2_system.hwh` — Hardware handoff (needed by PYNQ Python API)

Connect your PC and PYNQ-Z2 to the same LAN. The board default IP is `192.168.2.99`.

```bash
# Copy outputs to board
scp vivado_build/output/pynq_z2_system.bit  xilinx@192.168.2.99:/home/xilinx/
scp vivado_build/output/pynq_z2_system.hwh  xilinx@192.168.2.99:/home/xilinx/

# Default password: xilinx
```

Then open Jupyter Notebook in your browser at `http://192.168.2.99` and load the overlay:

```python
from pynq import Overlay
import pynq.lib.dma

ol = Overlay('/home/xilinx/pynq_z2_system.bit')

# AXI DMA for matrix data
dma = ol.axi_dma_0

# Read fault_detected from AXI GPIO (base address assigned by Vivado)
fault_gpio = ol.axi_gpio_fault
fault_status = fault_gpio.read(0)    # 1 = DMR mismatch detected
print(f"Fault status: {fault_status}")
```

---

## Step 6 — Checking Results & Fault Status

When a DMR PE detects a mismatch, `fault_detected` is set HIGH and readable via AXI GPIO. The PS can:

1. **Log the event** for reliability analysis
2. **Re-run the tile** (software retry)
3. **Flag the result** as low-confidence in the inference output

---

## Changing the Protection Map (Rebuild Required)

To change which PEs use TMR/DMR:
1. Edit `vivado_build/config/design_config.tcl`
2. Re-run the batch build command
3. The new bitstream reflects the new protection configuration

> **Each protection configuration produces a distinct bitstream.** The PS software does not change — only the hardware.

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| `blk_mem_gen_0` not found | IP not generated | Open project in GUI → Tools → Run Tcl Script → `02_create_project.tcl` again |
| Synthesis timing violations | Clock too fast, or large N | Reduce FCLK to 50 MHz in `03_create_bd.tcl` PS config |
| `systolic_protected.sv` not found | Gen script not run | Re-run `01_gen_protected_rtl.tcl` with config loaded |
| AXI Stream not connecting in BD | Interface mismatch | Check `mm_protected_axi.v` port names match BD interface names |
| Board not detected | SCP fails | Check LAN cable + `ping 192.168.2.99`; set board IP in `/etc/dhcpd.conf` |

---

## Vivado Version Notes

| Version | Status |
|---------|--------|
| **2022.2** | ✅ Primary target — fully tested flow |
| **2025.1** | ✅ Compatible — use same TCL (SmartConnect API unchanged) |
| **2021.1** | ⚠️ May work — `smartconnect` IP version may differ |
| **2020.2** | ⚠️ May work — replace `smartconnect` with `axi_interconnect` |
