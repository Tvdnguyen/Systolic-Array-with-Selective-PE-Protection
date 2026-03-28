`timescale 1ns / 1ps
// ============================================================
// mm_protected_axi.v  —  AXI-Stream wrapper for mm_protected
//
// Identical interface to mm_axi.v PLUS:
//   fault_detected  : 1-bit output, OR of all DMR error flags
//                     (connected to AXI GPIO in the block design)
// ============================================================
module mm_protected_axi
#(
    parameter M = 4,
    parameter N = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    // Incoming AXI-Stream (DMA MM2S → PL)
    input  wire [31:0] x_TDATA,
    input  wire        x_TVALID,
    output wire        x_TREADY,
    input  wire        x_TLAST,
    // Outgoing AXI-Stream (PL → DMA S2MM)
    output wire [31:0] y_TDATA,
    output wire        y_TVALID,
    input  wire        y_TREADY,
    output wire        y_TLAST,
    // Fault status (connect to AXI GPIO for PS to read)
    output wire        fault_detected
);

    mm_protected #(.M(M), .N(N), .D_W(8)) mm_protected_inst (
        .mm_clk    (clk),
        .mm_rst_n  (rst_n),

        .s_axis_s2mm_tdata  (x_TDATA),
        .s_axis_s2mm_tkeep  (),
        .s_axis_s2mm_tlast  (x_TLAST),
        .s_axis_s2mm_tready (x_TREADY),
        .s_axis_s2mm_tvalid (x_TVALID),

        .m_axis_mm2s_tdata  (y_TDATA),
        .m_axis_mm2s_tkeep  (),
        .m_axis_mm2s_tlast  (y_TLAST),
        .m_axis_mm2s_tready (y_TREADY),
        .m_axis_mm2s_tvalid (y_TVALID),

        .fault_detected     (fault_detected)
    );

endmodule
