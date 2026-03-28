`timescale 1ns/1ps
// tb_pe_ws_tmr.v — TMR correction for WS PE
module tb_pe_ws_tmr;
    parameter DW=8;
    reg clk,rst,init,in_valid;
    reg [DW-1:0] in_a,in_b; reg [2*DW-1:0] in_data;
    wire [DW-1:0] out_a,out_b; wire [2*DW-1:0] out_data; wire out_valid;

    pe_ws_tmr #(.D_W(DW),.i(0),.j(0)) dut (
        .clk(clk),.rst(rst),.init(init),
        .in_a(in_a),.in_b(in_b),.out_a(out_a),.out_b(out_b),
        .in_data(in_data),.in_valid(in_valid),
        .out_data(out_data),.out_valid(out_valid));

    wire [2*DW-1:0] ref_data = dut.out_data_A;
    always #5 clk=~clk;
    integer errors=0;

    initial begin
        clk=0;rst=1;init=0;in_a=0;in_b=0;in_data=0;in_valid=0;
        repeat(3) @(posedge clk); rst=0;
        // Load weight=4, compute
        init=1; in_b=8'd4; in_a=0; in_valid=1; in_data=0;
        @(posedge clk); #1; init=0; in_a=8'd5;
        repeat(3) @(posedge clk);
        // Fault in pe_ws_C
        force dut.pe_ws_C.out_data = 16'hAAAA;
        @(posedge clk); #1; @(posedge clk); #1;
        if (out_data === ref_data)
            $display("PASS: WS_TMR majority corrects pe_ws_C fault: out=%0d", out_data);
        else begin
            $display("FAIL: WS_TMR out=%0d != ref=%0d", out_data, ref_data);
            errors=errors+1;
        end
        release dut.pe_ws_C.out_data;
        if (errors==0) $display("PASS: pe_ws_tmr all tests");
        else           $display("FAIL: pe_ws_tmr %0d errors", errors);
        #20; $finish;
    end
    initial begin #3000; $display("FAIL: pe_ws_tmr TIMEOUT"); $finish; end
endmodule
