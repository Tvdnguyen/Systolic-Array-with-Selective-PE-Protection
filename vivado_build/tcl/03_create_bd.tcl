# ==============================================================
# 03_create_bd.tcl
#
# Creates the Block Design for PYNQ-Z2:
#
#   ARM Cortex-A9 (PS7)
#     → AXI Interconnect
#       → AXI DMA  (HP0 port: 64-bit, high bandwidth)
#           ↔ mm_protected_axi  (our systolic array module)
#       → AXI GPIO  (reads fault_detected from DMR PEs)
#
# Generates HDL wrapper and sets it as the synthesis top.
# ==============================================================

set BD_NAME "pynq_z2_system"
create_bd_design $BD_NAME
current_bd_design $BD_NAME

set N $DESIGN_N
set M $DESIGN_N

# ─────────────────────────────────────────────────────────────
# 1. Zynq Processing System (PS7)
# ─────────────────────────────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR"} \
    [get_bd_cells processing_system7_0]

# ── Configure PS7 manually for PYNQ-Z2 (MIO, DDR3, Clocks) ─────
# These parameters ensure the board boots and works without official board files.
set_property -dict [list \
    CONFIG.PCW_UIPARAM_DDR_PARTNO      {MT41K256M16 RE-125} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH   {16 Bit} \
    CONFIG.PCW_UIPARAM_DDR_BL          {8} \
    CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3} \
    CONFIG.PCW_PCAP_PERIPHERAL_FREQMHZ {200} \
    CONFIG.PCW_PRESET_BANK0_VOLTAGE    {LVCMOS 3.3V} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE    {LVCMOS 1.8V} \
    CONFIG.PCW_USE_S_AXI_HP0           {1} \
    CONFIG.PCW_S_AXI_HP0_DATA_WIDTH    {64} \
    CONFIG.PCW_EN_CLK0_PORT            {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_EN_UART0                {1} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART0_UART0_IO          {MIO 14 .. 15} \
    CONFIG.PCW_EN_ENET0                {1} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_ENET0_IO          {MIO 16 .. 27} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE   {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO       {MIO 52 .. 53} \
    CONFIG.PCW_EN_USB0                 {1} \
    CONFIG.PCW_USB0_PERIPHERAL_ENABLE  {1} \
    CONFIG.PCW_USB0_USB0_IO            {MIO 28 .. 39} \
    CONFIG.PCW_EN_SDIO0                {1} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE   {1} \
    CONFIG.PCW_SD0_SD0_IO              {MIO 40 .. 45} \
    CONFIG.PCW_SD0_GRP_CD_ENABLE       {1} \
    CONFIG.PCW_SD0_GRP_CD_IO           {MIO 47} \
    CONFIG.PCW_EN_GPIO                 {1} \
    CONFIG.PCW_GPIO_MIO_GPIO_ENABLE    {1} \
    CONFIG.PCW_QSPI_PERIPHERAL_ENABLE  {1} \
    CONFIG.PCW_QSPI_QSPI_IO            {MIO 1 .. 6} \
    CONFIG.PCW_QSPI_GRP_FBCLK_ENABLE   {1} \
    CONFIG.PCW_QSPI_GRP_FBCLK_IO       {MIO 8} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT    {1} \
    CONFIG.PCW_IRQ_F2P_INTR            {1} \
] [get_bd_cells processing_system7_0]

# ─────────────────────────────────────────────────────────────
# 2. AXI DMA (no Scatter-Gather, simple direct register mode)
# ─────────────────────────────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0

set_property -dict [list \
    CONFIG.c_include_sg              {0}   \
    CONFIG.c_include_mm2s            {1}   \
    CONFIG.c_include_s2mm            {1}   \
    CONFIG.c_m_axi_mm2s_data_width   {64}  \
    CONFIG.c_m_axis_mm2s_tdata_width {32}  \
    CONFIG.c_m_axi_s2mm_data_width   {64}  \
    CONFIG.c_s_axis_s2mm_tdata_width {32}  \
    CONFIG.c_sg_length_width         {23}  \
    CONFIG.c_mm2s_burst_size         {16}  \
    CONFIG.c_s2mm_burst_size         {16}  \
    CONFIG.c_sg_include_stscntrl_strm {0}  \
] [get_bd_cells axi_dma_0]

# ─────────────────────────────────────────────────────────────
# 3. mm_protected_axi (our systolic array, added as RTL module)
# ─────────────────────────────────────────────────────────────
create_bd_cell -type module -reference mm_protected_axi mm_eval

set_property -dict [list \
    CONFIG.M $M \
    CONFIG.N $N \
] [get_bd_cells mm_eval]

# ─────────────────────────────────────────────────────────────
# 4. AXI GPIO (1-bit input: reads fault_detected from PL)
# ─────────────────────────────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_fault

set_property -dict [list \
    CONFIG.C_GPIO_WIDTH  {1}   \
    CONFIG.C_ALL_INPUTS  {1}   \
    CONFIG.C_ALL_OUTPUTS {0}   \
] [get_bd_cells axi_gpio_fault]

# ─────────────────────────────────────────────────────────────
# 5. AXI SmartConnect (PS GP0 → DMA + GPIO)
# ─────────────────────────────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_sc_gp0
set_property CONFIG.NUM_SI {1} [get_bd_cells axi_sc_gp0]
set_property CONFIG.NUM_MI {2} [get_bd_cells axi_sc_gp0]

# ─────────────────────────────────────────────────────────────
# 6. AXI SmartConnect (DMA → PS HP0)
# ─────────────────────────────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_sc_hp0
set_property CONFIG.NUM_SI {2} [get_bd_cells axi_sc_hp0]
set_property CONFIG.NUM_MI {1} [get_bd_cells axi_sc_hp0]

# ─────────────────────────────────────────────────────────────
# 7. Clock & Reset
# ─────────────────────────────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0

# ─────────────────────────────────────────────────────────────
# 8. Connect clocks (FCLK_CLK0 feeds everything)
# ─────────────────────────────────────────────────────────────
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]   \
    [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]   \
    [get_bd_pins axi_dma_0/s_axi_lite_aclk]             \
    [get_bd_pins axi_dma_0/m_axi_mm2s_aclk]             \
    [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]             \
    [get_bd_pins mm_eval/clk]                            \
    [get_bd_pins axi_gpio_fault/s_axi_aclk]             \
    [get_bd_pins proc_sys_reset_0/slowest_sync_clk]      \
    [get_bd_pins axi_sc_gp0/aclk]                        \
    [get_bd_pins axi_sc_hp0/aclk]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins proc_sys_reset_0/ext_reset_in]

connect_bd_net [get_bd_pins proc_sys_reset_0/interconnect_aresetn] \
    [get_bd_pins axi_sc_gp0/aresetn]                     \
    [get_bd_pins axi_sc_hp0/aresetn]

connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
    [get_bd_pins axi_dma_0/axi_resetn]                   \
    [get_bd_pins mm_eval/rst_n]                          \
    [get_bd_pins axi_gpio_fault/s_axi_aresetn]

# ─────────────────────────────────────────────────────────────
# 9. AXI data connections
# ─────────────────────────────────────────────────────────────
# GP0 → SmartConnect → DMA (lite ctrl) + GPIO (lite ctrl)
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
    [get_bd_intf_pins axi_sc_gp0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_sc_gp0/M00_AXI] \
    [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_sc_gp0/M01_AXI] \
    [get_bd_intf_pins axi_gpio_fault/S_AXI]

# DMA memory ports → SmartConnect → HP0
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] \
    [get_bd_intf_pins axi_sc_hp0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] \
    [get_bd_intf_pins axi_sc_hp0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_sc_hp0/M00_AXI] \
    [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# AXI-Stream: DMA MM2S → mm_eval input (PS sends data to PL)
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] \
    [get_bd_intf_pins mm_eval/x]

# AXI-Stream: mm_eval output → DMA S2MM (PL sends result to PS)
connect_bd_intf_net [get_bd_intf_pins mm_eval/y] \
    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# fault_detected → GPIO input
connect_bd_net [get_bd_pins mm_eval/fault_detected] \
    [get_bd_pins axi_gpio_fault/gpio_io_i]

# DMA interrupt → PS interrupt
connect_bd_net [get_bd_pins axi_dma_0/mm2s_introut] \
    [get_bd_pins processing_system7_0/IRQ_F2P]

# ─────────────────────────────────────────────────────────────
# 10. Assign addresses
# ─────────────────────────────────────────────────────────────
assign_bd_address

# ─────────────────────────────────────────────────────────────
# 11. Validate and save
# ─────────────────────────────────────────────────────────────
validate_bd_design
save_bd_design

# ── Generate HDL wrapper and set as Top ───────────────────────
set bd_file [get_files -all -filter {NAME =~ "*pynq_z2_system.bd"}]
if {$bd_file eq ""} {
    error "ERROR: Could not find Block Design file (pynq_z2_system.bd)"
}
set wrapper_file [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper_file
set_property top ${BD_NAME}_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "  ✓ Block Design created: $BD_NAME"
puts "    AXI GPIO fault register base address:"
foreach cell [get_bd_cells axi_gpio_fault] {
    set segs [get_bd_addr_segs -of_objects $cell]
    foreach seg $segs { puts "      [get_property OFFSET $seg]" }
}
