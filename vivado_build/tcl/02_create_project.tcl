# ==============================================================
# 02_create_project.tcl
#
# Creates Vivado project, adds RTL sources and constraints.
# Assumes design_config.tcl already sourced
# (DESIGN_N, DESIGN_D_W, DESIGN_DATAFLOW, PE_PROTECTION_MAP).
# ==============================================================

set SCRIPT_DIR  [file dirname [file normalize [info script]]]
set BUILD_DIR   [file normalize "$SCRIPT_DIR/.."]
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
set_property target_language Verilog [current_project]

# ── Check generated file ──────────────────────────────────────
set gen_file "$BUILD_DIR/generated/systolic_protected.sv"
if {![file exists $gen_file]} {
    error "ERROR: systolic_protected.sv not found. Run 01_gen_protected_rtl.tcl first."
}

# ── Select PE files based on DATAFLOW ────────────────────────
# Only add PE files relevant to the current dataflow.
# Unused dataflow files (e.g. pe_ws.v for an IS design) would appear
# as orphan (un-instantiated) modules, confusing update_compile_order
# into picking them as the top-level module instead of pynq_z2_system_wrapper.
switch $DESIGN_DATAFLOW {
    "IS" {
        set pe_base_file  "$BUILD_DIR/rtl/pe_is.v"
        set pe_dmr_file   "$BUILD_DIR/rtl/pe_is_dmr.v"
        set pe_tmr_file   "$BUILD_DIR/rtl/pe_is_tmr.v"
    }
    "WS" {
        set pe_base_file  "$BUILD_DIR/rtl/pe_ws.v"
        set pe_dmr_file   "$BUILD_DIR/rtl/pe_ws_dmr.v"
        set pe_tmr_file   "$BUILD_DIR/rtl/pe_ws_tmr.v"
    }
    "OS" {
        set pe_base_file  "$BUILD_DIR/rtl/pe.v"
        set pe_dmr_file   "$BUILD_DIR/rtl/pe_dmr.v"
        set pe_tmr_file   "$BUILD_DIR/rtl/pe_tmr.v"
    }
}

# Determine which protection variants are actually used
set need_dmr 0
set need_tmr 0
foreach entry $PE_PROTECTION_MAP {
    set m [lindex $entry 2]
    if {$m eq "DMR"} { set need_dmr 1 }
    if {$m eq "TMR"} { set need_tmr 1 }
}

# ── Core RTL files (always needed) ───────────────────────────
set rtl_files [list \
    $pe_base_file                        \
    "$BUILD_DIR/rtl/counter.v"           \
    "$BUILD_DIR/rtl/mem_read_m0.sv"      \
    "$BUILD_DIR/rtl/mem_read_m1.sv"      \
    "$BUILD_DIR/rtl/mem_write.sv"        \
    "$BUILD_DIR/rtl/pipe.sv"             \
    $gen_file                            \
    "$BUILD_DIR/rtl/mm_protected.sv"     \
    "$BUILD_DIR/rtl/mm_protected_axi.v"  \
]

# Add protection variant PE files only if they're actually used
if {$need_dmr} { lappend rtl_files $pe_dmr_file }
if {$need_tmr} { lappend rtl_files $pe_tmr_file }

puts "  RTL files to add: [llength $rtl_files]"
puts "    Dataflow: $DESIGN_DATAFLOW  | DMR: $need_dmr  | TMR: $need_tmr"
foreach f $rtl_files { puts "    $f" }

add_files $rtl_files

# ── Create Block Memory Generator IP ─────────────────────────
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

# ── Single update_compile_order after all relevant files ─────
# With only the relevant PE files for this dataflow added,
# update_compile_order correctly determines pynq_z2_system_wrapper as top.
update_compile_order -fileset sources_1

puts "  ✓ Project created at: $PROJ_DIR"
puts "    Part: $PART  |  BRAM depth: $bram_depth  |  N=$N  M=$M"
puts "    Auto-detected top after add: [get_property top [current_fileset]]"
