# ==============================================================
# run_all.tcl  —  Master Build Script
#
# Usage (batch mode — recommended):
#   vivado -mode batch -source vivado_build/tcl/run_all.tcl
#
# Usage (Tcl console inside an open Vivado session):
#   source vivado_build/tcl/run_all.tcl
#
# The script reads configuration from:
#   vivado_build/config/design_config.tcl
# ==============================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set BUILD_DIR  [file normalize "$SCRIPT_DIR/.."]

# ── Banner ────────────────────────────────────────────────────
puts ""
puts "╔══════════════════════════════════════════════════════╗"
puts "  PYNQ-Z2 Systolic Array w/ Selective PE Protection"
puts "  Vivado 2022.2 Build Flow"
puts "╚══════════════════════════════════════════════════════╝"

# ── Step 1: Load user configuration ──────────────────────────
puts "\n\[1/4\] Loading design_config.tcl..."
source "$BUILD_DIR/config/design_config.tcl"
puts "       N=$DESIGN_N  D_W=$DESIGN_D_W"
puts "       Protection entries: [llength $PE_PROTECTION_MAP]"
foreach e $PE_PROTECTION_MAP {
    set mode [lindex $e 2]
    if {$mode ne "none"} { puts "         PE([lindex $e 0],[lindex $e 1]) → $mode" }
}

# ── Step 2: Generate protected RTL ───────────────────────────
puts "\n\[2/4\] Generating systolic_protected.sv..."
source "$SCRIPT_DIR/01_gen_protected_rtl.tcl"

# ── Step 3: Create Vivado project + add sources ───────────────
puts "\n\[3/4\] Creating Vivado project..."
source "$SCRIPT_DIR/02_create_project.tcl"

# ── Step 4: Create Block Design ──────────────────────────────
puts "\n\[4/4\] Building Block Design (PS + PL)..."
source "$SCRIPT_DIR/03_create_bd.tcl"

# ── Step 5: Synthesize, Implement, Write Bitstream ───────────
puts "\n\[5/4\] Synthesis → Implementation → Bitstream..."
source "$SCRIPT_DIR/04_synth_impl.tcl"
