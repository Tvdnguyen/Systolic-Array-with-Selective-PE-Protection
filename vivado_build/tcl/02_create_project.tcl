# ==============================================================
# 02_create_project.tcl
#
# Creates Vivado project, adds all RTL sources and constraints.
# Assumes design_config.tcl already sourced (DESIGN_N, DESIGN_D_W).
# ==============================================================

set SCRIPT_DIR  [file dirname [file normalize [info script]]]
set BUILD_DIR   [file normalize "$SCRIPT_DIR/.."]
set SRC_DIR     [file normalize "$BUILD_DIR/.."]   ;# original source
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
set_property board_part tul.com.tw:pynq-z2:part0:1.0 [current_project]
set_property target_language Verilog [current_project]

# ── Add original RTL sources (from parent directory) ─────────
add_files [list \
    "$SRC_DIR/pe.v"            \
    "$SRC_DIR/pe_unpipelined.v"\
    "$SRC_DIR/counter.v"       \
    "$SRC_DIR/mem_read_m0.sv"  \
    "$SRC_DIR/mem_read_m1.sv"  \
    "$SRC_DIR/mem_write.sv"    \
    "$SRC_DIR/pipe.sv"         \
]

# ── Add new protected RTL (build/rtl) ────────────────────────
# OS protection wrappers
add_files [list \
    "$BUILD_DIR/rtl/pe_dmr.v"            \
    "$BUILD_DIR/rtl/pe_tmr.v"            \
]
# WS PE variants
add_files [list \
    "$BUILD_DIR/rtl/pe_ws.v"             \
    "$BUILD_DIR/rtl/pe_ws_dmr.v"         \
    "$BUILD_DIR/rtl/pe_ws_tmr.v"         \
]
# IS PE variants
add_files [list \
    "$BUILD_DIR/rtl/pe_is.v"             \
    "$BUILD_DIR/rtl/pe_is_dmr.v"         \
    "$BUILD_DIR/rtl/pe_is_tmr.v"         \
]
# Controller & AXI wrapper
add_files [list \
    "$BUILD_DIR/rtl/mm_protected.sv"     \
    "$BUILD_DIR/rtl/mm_protected_axi.v"  \
]

# ── Add generated systolic_protected.sv ──────────────────────
set gen_file "$BUILD_DIR/generated/systolic_protected.sv"
if {![file exists $gen_file]} {
    error "ERROR: systolic_protected.sv not found. Run 01_gen_protected_rtl.tcl first."
}
add_files $gen_file

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
    CONFIG.Enable_A             {Always_Enabled}         \
    CONFIG.Enable_B             {Always_Enabled}         \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Use_RSTA_Pin         {false}                  \
    CONFIG.Use_RSTB_Pin         {false}                  \
] [get_ips blk_mem_gen_0]

generate_target all [get_ips blk_mem_gen_0]

# ── Add XDC constraints ───────────────────────────────────────
add_files -fileset constrs_1 "$BUILD_DIR/constraints/pynq_z2.xdc"

# ── Set top (used for RTL simulation; Block Design sets its own top) ────
set_property top mm_protected_axi [current_fileset]

puts "  ✓ Project created at: $PROJ_DIR"
puts "    Part: $PART  |  BRAM depth: $bram_depth  |  N=$N  M=$M"
