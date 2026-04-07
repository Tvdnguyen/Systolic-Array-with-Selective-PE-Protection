# ==============================================================
# 02_create_project.tcl
#
# Creates Vivado project, adds all RTL sources and constraints.
# Assumes design_config.tcl already sourced (DESIGN_N, DESIGN_D_W).
# ==============================================================

set SCRIPT_DIR  [file dirname [file normalize [info script]]]
set BUILD_DIR   [file normalize "$SCRIPT_DIR/.."]
set SRC_DIR     [file normalize "$BUILD_DIR/..\"]   ;# original source
set PROJ_DIR    "$BUILD_DIR/project"
set PROJ_NAME   "mm_protected_system"
set PART        "xc7z020clg400-1"                  ;# PYNQ-Z2

# ── Remove old project if exists ─────────────────────────────
if {[file exists "$PROJ_DIR/$PROJ_NAME.xpr"]} {
    file delete -force $PROJ_DIR
}
file mkdir $PROJ_DIR

# ── Create project ────────────────────────────────────────────
create_project $PROJ_NAME $PROJ_DIR -part $PART
# set_property board_part tul.com.tw:pynq-z2:part0:1.0 [current_project]
set_property target_language Verilog [current_project]

# ── Check generated file exists ──────────────────────────────
set gen_file "$BUILD_DIR/generated/systolic_protected.sv"
if {![file exists $gen_file]} {
    error "ERROR: systolic_protected.sv not found. Run 01_gen_protected_rtl.tcl first."
}

# ── Add ALL RTL sources together (including generated files) ──
# IMPORTANT: systolic_protected.sv must be added in the SAME batch as
# pe_is_tmr.v so that update_compile_order knows pe_is_tmr is instantiated
# by systolic_protected → pe_is_tmr is NOT a top-level candidate.
set rtl_files [list \
    "$BUILD_DIR/rtl/pe.v"                \
    "$BUILD_DIR/rtl/counter.v"           \
    "$BUILD_DIR/rtl/mem_read_m0.sv"      \
    "$BUILD_DIR/rtl/mem_read_m1.sv"      \
    "$BUILD_DIR/rtl/mem_write.sv"        \
    "$BUILD_DIR/rtl/pipe.sv"             \
    "$BUILD_DIR/rtl/systolic.sv"         \
    $gen_file                            \
    "$BUILD_DIR/rtl/pe_dmr.v"            \
    "$BUILD_DIR/rtl/pe_tmr.v"            \
    "$BUILD_DIR/rtl/pe_ws.v"             \
    "$BUILD_DIR/rtl/pe_ws_dmr.v"         \
    "$BUILD_DIR/rtl/pe_ws_tmr.v"         \
    "$BUILD_DIR/rtl/pe_is.v"             \
    "$BUILD_DIR/rtl/pe_is_dmr.v"         \
    "$BUILD_DIR/rtl/pe_is_tmr.v"         \
    "$BUILD_DIR/rtl/mm.sv"               \
    "$BUILD_DIR/rtl/mm_axi.v"            \
    "$BUILD_DIR/rtl/mm_protected.sv"     \
    "$BUILD_DIR/rtl/mm_protected_axi.v"  \
]

add_files $rtl_files

# ── Create Block Memory Generator IP ─────────────────────────
# blk_mem_gen_0: True Dual Port, 32-bit width, depth = (M*M)/N
# Used for M0, M1 (input banks) and M2 (output bank in mm_protected.sv)
set M $DESIGN_N
set N $DESIGN_N
set DW $DESIGN_D_W
set bram_depth [expr {($M * $M) / $N}]

create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 \
          -module_name blk_mem_gen_0

set_property -dict [list \
    CONFIG.Memory_Type          {True_Dual_Port_RAM}     \
    CONFIG.Write_Width_A        {32}                     \
    CONFIG.Read_Width_A         {32}                     \
    CONFIG.Write_Depth_A        $bram_depth              \
    CONFIG.Write_Width_B        {32}                     \
    CONFIG.Read_Width_B         {32}                     \
    CONFIG.Enable_A             {Use_ENA_Pin}            \
    CONFIG.Enable_B             {Use_ENB_Pin}            \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Use_RSTA_Pin         {false}                  \
    CONFIG.Use_RSTB_Pin         {false}                  \
] [get_ips blk_mem_gen_0]

generate_target all [get_ips blk_mem_gen_0]

# ── Add XDC constraints ───────────────────────────────────────
add_files -fileset constrs_1 "$BUILD_DIR/constraints/pynq_z2.xdc"

# ── Single update_compile_order after all files are added ─────
# With systolic_protected.sv in the same batch as pe_is_tmr.v,
# Vivado now knows pe_is_tmr is NOT a top, and mm_protected_axi is
# instantiated by the BD, so pynq_z2_system_wrapper becomes the top.
update_compile_order -fileset sources_1

puts "  ✓ Project created at: $PROJ_DIR"
puts "    Part: $PART  |  BRAM depth: $bram_depth  |  N=$N  M=$M"
puts "    Auto-detected top: [get_property top [current_fileset]]"
