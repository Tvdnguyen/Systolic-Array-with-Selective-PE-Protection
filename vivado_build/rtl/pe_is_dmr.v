`timescale 1ns / 1ps
// pe_is_dmr.v — Input Stationary PE with Dual Modular Redundancy
module pe_is_dmr
#(parameter D_W=8, parameter i=0, parameter j=0)
(
    input  wire              clk, rst, init,
    input  wire [D_W-1:0]   in_a, in_b,
    output wire [D_W-1:0]   out_a, out_b,
    input  wire [2*D_W-1:0] in_data,
    input  wire              in_valid,
    output wire [2*D_W-1:0] out_data,
    output wire              out_valid,
    output reg               error_flag
);
    wire [D_W-1:0]   out_a_A, out_b_A; wire [2*D_W-1:0] out_data_A; wire out_valid_A;
    wire [D_W-1:0]   out_a_B, out_b_B; wire [2*D_W-1:0] out_data_B; wire out_valid_B;

    pe_is #(.D_W(D_W),.i(i),.j(j)) pe_is_A (
        .clk(clk),.rst(rst),.init(init),.in_a(in_a),.in_b(in_b),
        .out_a(out_a_A),.out_b(out_b_A),
        .in_data(in_data),.in_valid(in_valid),
        .out_data(out_data_A),.out_valid(out_valid_A));

    pe_is #(.D_W(D_W),.i(i),.j(j)) pe_is_B (
        .clk(clk),.rst(rst),.init(init),.in_a(in_a),.in_b(in_b),
        .out_a(out_a_B),.out_b(out_b_B),
        .in_data(in_data),.in_valid(in_valid),
        .out_data(out_data_B),.out_valid(out_valid_B));

    assign out_a    = out_a_A;
    assign out_b    = out_b_A;
    assign out_data = out_data_A;
    assign out_valid= out_valid_A;

    always @(posedge clk) begin
        if (rst) error_flag <= 0;
        else     error_flag <= (out_data_A != out_data_B) ||
                               (out_valid_A != out_valid_B) ||
                               (out_a_A    != out_a_B);
    end
endmodule
