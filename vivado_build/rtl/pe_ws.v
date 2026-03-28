`timescale 1ns / 1ps
// ============================================================
// pe_ws.v  —  Weight Stationary Processing Element
//
// DATAFLOW ANALYSIS (vs Output Stationary pe.v):
// ┌────────────────┬──────────────────┬──────────────────────┐
// │                │   OS  (pe.v)     │   WS  (pe_ws.v)      │
// ├────────────────┼──────────────────┼──────────────────────┤
// │ Stationary     │ Output (psum)    │ Weight (B matrix)    │
// │ Register       │ out_tmp          │ w_reg                │
// │ in_a role      │ Activation A     │ Activation A (same)  │
// │ in_b role      │ Weight B (flows) │ Weight B (LOAD only) │
// │ out_a          │ pass-through A   │ pass-through A       │
// │ out_b          │ pass-through B   │ pass-through B*      │
// │ psum path      │ local in PE      │ flows RIGHT via      │
// │                │                  │ in_data→out_data     │
// │ init=1 means   │ flush & output   │ LOAD weight from     │
// │                │ current psum     │ in_b → w_reg         │
// └────────────────┴──────────────────┴──────────────────────┘
//
// * out_b passes in_b through so diagonal loading can fill
//   deeper rows of the systolic array the same way as OS.
//
// OPERATION SEQUENCE:
//   Phase 1 (LOAD, N cycles):
//     init=1; in_b carries one weight element per cycle
//     → each PE captures its weight at the right diagonal time
//     → systolic controller uses the same diagonal `init` generator
//       from systolic.sv to stagger loads across the NxN grid
//
//   Phase 2 (COMPUTE, M cycles per tile):
//     init=0; in_a carries activation elements (A matrix)
//     → PE computes:  psum_out = psum_in + A_pipe * w_reg
//     → partial sum flows RIGHT via OutputDataWire
//     → right edge of array collects C[row][j]
//
// MATHEMATICAL RESULT:
//   m2[r] = sum_{c=0}^{N-1}  A[r][c] * B_loaded[r][c]
//   (inner product of row r of A with the loaded weight row)
//   Full C = A × B is obtained by pipelining M/N tiles.
// ============================================================
module pe_ws
#(
    parameter D_W = 8,
    parameter i   = 0,
    parameter j   = 0
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              init,       // 1 = LOAD phase, 0 = COMPUTE phase
    input  wire [D_W-1:0]   in_a,       // activation A (flows horizontally)
    input  wire [D_W-1:0]   in_b,       // weight B (loaded when init=1, then frozen)
    output wire [D_W-1:0]   out_a,      // A pass-through to next column
    output wire [D_W-1:0]   out_b,      // B pass-through to next row (for loading)
    input  wire [2*D_W-1:0] in_data,    // incoming partial sum from left
    input  wire              in_valid,
    output reg  [2*D_W-1:0] out_data,   // outgoing partial sum to right
    output reg               out_valid
);

    // ── Internal registers ────────────────────────────────────
    reg [D_W-1:0]   w_reg;          // STATIONARY weight (loaded once)
    reg [D_W-1:0]   a_pipe;         // pipeline register for in_a
    reg [D_W-1:0]   b_pipe;         // pipeline register for in_b (pass-through)
    reg [2*D_W-1:0] product_r;      // registered product: a_pipe * w_reg
    reg [2*D_W-1:0] in_data_r;      // registered incoming partial sum
    reg             in_valid_r;
    reg             init_r;

    always @(posedge clk) begin
        if (rst) begin
            w_reg      <= 0;  a_pipe   <= 0;  b_pipe   <= 0;
            product_r  <= 0;  in_data_r<= 0;  in_valid_r<= 0;
            init_r     <= 0;  out_data <= 0;   out_valid <= 0;
        end else begin
            // ── Pipeline stage 1: register inputs ─────────────
            a_pipe     <= in_a;
            b_pipe     <= in_b;
            in_data_r  <= in_data;
            in_valid_r <= in_valid;
            init_r     <= init;

            // ── Weight capture (LOAD phase) ───────────────────
            //    Diagonal wavefront: init[r][c] fires when r+c==slice
            //    Each PE captures its weight at its own init pulse
            if (init)
                w_reg <= in_b;

            // ── Pipeline stage 2: compute product ────────────
            product_r <= in_a * w_reg;

            // ── Pipeline stage 3: accumulate / pass ──────────
            if (!init_r) begin
                // COMPUTE phase: add product to incoming psum
                out_data  <= in_data_r + product_r;
                out_valid <= in_valid_r;
            end else begin
                // LOAD phase: zero out the psum chain
                out_data  <= 0;
                out_valid <= 0;
            end
        end
    end

    // ── Pass-throughs ─────────────────────────────────────────
    assign out_a = a_pipe;   // activation continues to next column
    assign out_b = b_pipe;   // weight routes to next row for loading

endmodule
