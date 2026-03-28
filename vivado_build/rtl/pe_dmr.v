`timescale 1ns / 1ps
// ============================================================
// pe_dmr.v  —  Dual Modular Redundancy PE Wrapper
//
// Instantiates 2 identical pe.v copies (pe_A, pe_B).
// - pe_A drives all outputs (primary).
// - pe_B is the checker copy.
// - If pe_A output diverges from pe_B, error_flag is asserted
//   for that clock cycle.
//
// Overhead vs plain pe: ~2x LUTs, ~2x DSPs, no net latency.
// ============================================================
module pe_dmr
#(
    parameter D_W = 8,
    parameter i   = 0,
    parameter j   = 0
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              init,
    input  wire [D_W-1:0]   in_a,
    input  wire [D_W-1:0]   in_b,
    output wire [D_W-1:0]   out_a,
    output wire [D_W-1:0]   out_b,
    input  wire [2*D_W-1:0] in_data,
    input  wire              in_valid,
    output wire [2*D_W-1:0] out_data,
    output wire              out_valid,
    output reg               error_flag   // 1 → mismatch detected this cycle
);

    // ── Primary copy A ───────────────────────────────────────
    wire [D_W-1:0]   out_a_A,    out_b_A;
    wire [2*D_W-1:0] out_data_A;
    wire             out_valid_A;

    pe #(.D_W(D_W),.i(i),.j(j)) pe_A (
        .clk(clk), .rst(rst), .init(init),
        .in_a(in_a),       .in_b(in_b),
        .out_a(out_a_A),   .out_b(out_b_A),
        .in_data(in_data), .in_valid(in_valid),
        .out_data(out_data_A), .out_valid(out_valid_A)
    );

    // ── Checker copy B ───────────────────────────────────────
    wire [D_W-1:0]   out_a_B,    out_b_B;
    wire [2*D_W-1:0] out_data_B;
    wire             out_valid_B;

    pe #(.D_W(D_W),.i(i),.j(j)) pe_B (
        .clk(clk), .rst(rst), .init(init),
        .in_a(in_a),       .in_b(in_b),
        .out_a(out_a_B),   .out_b(out_b_B),
        .in_data(in_data), .in_valid(in_valid),
        .out_data(out_data_B), .out_valid(out_valid_B)
    );

    // ── Primary outputs from pe_A ────────────────────────────
    assign out_a    = out_a_A;
    assign out_b    = out_b_A;
    assign out_data = out_data_A;
    assign out_valid= out_valid_A;

    // ── Comparator  (registered for timing closure) ──────────
    always @(posedge clk) begin
        if (rst)
            error_flag <= 1'b0;
        else
            error_flag <= (out_data_A  != out_data_B)  ||
                          (out_valid_A != out_valid_B)  ||
                          (out_a_A     != out_a_B);
    end

endmodule
