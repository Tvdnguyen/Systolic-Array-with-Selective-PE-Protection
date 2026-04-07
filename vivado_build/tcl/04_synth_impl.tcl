# ==============================================================
# 04_synth_impl.tcl
#
# Runs: Synthesis → Implementation → Bitstream generation
# Copies outputs to vivado_build/output/
# ==============================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set BUILD_DIR  [file normalize "$SCRIPT_DIR/.."]
set OUT_DIR    "$BUILD_DIR/output"
file mkdir $OUT_DIR

# ── Confirm top module before synthesis ──────────────────────
# Top was set in 03_create_bd.tcl. With only dataflow-relevant RTL files
# added in 02_create_project.tcl, update_compile_order should have
# auto-detected pynq_z2_system_wrapper as top already.
set_property top pynq_z2_system_wrapper [current_fileset]
puts "  Top module (fileset)    : [get_property top [current_fileset]]"
puts "  Source mgmt mode        : [get_property source_mgmt_mode [current_project]]"


# ── Synthesis ─────────────────────────────────────────────────
puts "  [clock format [clock seconds] -format {%H:%M:%S}]  Launching synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "ERROR: Synthesis failed. Check vivado.log for details."
}

puts "  ✓ Synthesis complete."

# ── Implementation + Bitstream in one run ────────────────────
puts "  [clock format [clock seconds] -format {%H:%M:%S}]  Launching implementation..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "ERROR: Implementation failed. Check vivado.log for details."
}
puts "  ✓ Implementation and bitstream complete."

# ── Copy outputs ─────────────────────────────────────────────
set proj_dir [get_property DIRECTORY [current_project]]
set bd_name  "pynq_z2_system"

# Bitstream
set bit_src [glob -nocomplain "$proj_dir/impl_1/*.bit"]
if {[llength $bit_src] == 0} {
    set bit_src [glob -nocomplain \
        "$proj_dir/mm_protected_system.runs/impl_1/*.bit"]
}
if {[llength $bit_src] > 0} {
    file copy -force [lindex $bit_src 0] "$OUT_DIR/${bd_name}.bit"
    puts "  ✓ Bitstream → $OUT_DIR/${bd_name}.bit"
}

# HWH (Hardware Handoff — needed by PYNQ overlay)
set hwh_src [glob -nocomplain \
    "$proj_dir/**/${bd_name}.hwh"]
if {[llength $hwh_src] > 0} {
    file copy -force [lindex $hwh_src 0] "$OUT_DIR/${bd_name}.hwh"
    puts "  ✓ HWH file  → $OUT_DIR/${bd_name}.hwh"
} else {
    puts "  WARNING: .hwh not found. Check Vivado project BD files."
}

# Print resource utilization summary
report_utilization -file "$OUT_DIR/utilization.rpt"
report_timing_summary -file "$OUT_DIR/timing.rpt"

puts ""
puts "╔══════════════════════════════════════════════════════╗"
puts "  BUILD COMPLETE — outputs in $OUT_DIR"
puts "  Upload to PYNQ-Z2:"
puts "    scp $OUT_DIR/${bd_name}.bit   xilinx@<board_ip>:/home/xilinx/"
puts "    scp $OUT_DIR/${bd_name}.hwh   xilinx@<board_ip>:/home/xilinx/"
puts "╚══════════════════════════════════════════════════════╝"
