`timescale 1ns / 1ps
// pe_ws_tmr.v — Weight Stationary PE with Triple Modular Redundancy
// 3x pe_ws instances; bitwise 2-of-3 majority voter selects output.
module pe_ws_tmr
#(parameter D_W=8, parameter i=0, parameter j=0)
(
    input  wire              clk, rst, init,
    input  wire [D_W-1:0]   in_a, in_b,
    output wire [D_W-1:0]   out_a, out_b,
    input  wire [2*D_W-1:0] in_data,
    input  wire              in_valid,
    output wire [2*D_W-1:0] out_data,
    output wire              out_valid
);
    wire [D_W-1:0]   out_a_A,out_b_A; wire [2*D_W-1:0] out_data_A; wire out_valid_A;
    wire [D_W-1:0]   out_a_B,out_b_B; wire [2*D_W-1:0] out_data_B; wire out_valid_B;
    wire [D_W-1:0]   out_a_C,out_b_C; wire [2*D_W-1:0] out_data_C; wire out_valid_C;

    pe_ws #(.D_W(D_W),.i(i),.j(j)) pe_ws_A (
        .clk(clk),.rst(rst),.init(init),.in_a(in_a),.in_b(in_b),
        .out_a(out_a_A),.out_b(out_b_A),.in_data(in_data),.in_valid(in_valid),
        .out_data(out_data_A),.out_valid(out_valid_A));
    pe_ws #(.D_W(D_W),.i(i),.j(j)) pe_ws_B (
        .clk(clk),.rst(rst),.init(init),.in_a(in_a),.in_b(in_b),
        .out_a(out_a_B),.out_b(out_b_B),.in_data(in_data),.in_valid(in_valid),
        .out_data(out_data_B),.out_valid(out_valid_B));
    pe_ws #(.D_W(D_W),.i(i),.j(j)) pe_ws_C (
        .clk(clk),.rst(rst),.init(init),.in_a(in_a),.in_b(in_b),
        .out_a(out_a_C),.out_b(out_b_C),.in_data(in_data),.in_valid(in_valid),
        .out_data(out_data_C),.out_valid(out_valid_C));

    assign out_data  = (out_data_A  & out_data_B)  | (out_data_B  & out_data_C)  | (out_data_A  & out_data_C);
    assign out_valid = (out_valid_A & out_valid_B) | (out_valid_B & out_valid_C) | (out_valid_A & out_valid_C);
    assign out_a     = (out_a_A & out_a_B) | (out_a_B & out_a_C) | (out_a_A & out_a_C);
    assign out_b     = (out_b_A & out_b_B) | (out_b_B & out_b_C) | (out_b_A & out_b_C);
endmodule
