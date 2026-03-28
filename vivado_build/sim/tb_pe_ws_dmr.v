`timescale 1ns/1ps
// tb_pe_ws_dmr.v — DMR fault detection for WS PE (pe_ws_dmr.v)
module tb_pe_ws_dmr;
    parameter DW = 8;
    reg clk,rst,init,in_valid;
    reg [DW-1:0] in_a,in_b; reg [2*DW-1:0] in_data;
    wire [DW-1:0] out_a,out_b; wire [2*DW-1:0] out_data; wire out_valid,error_flag;

    pe_ws_dmr #(.D_W(DW),.i(0),.j(0)) dut (
        .clk(clk),.rst(rst),.init(init),
        .in_a(in_a),.in_b(in_b),.out_a(out_a),.out_b(out_b),
        .in_data(in_data),.in_valid(in_valid),
        .out_data(out_data),.out_valid(out_valid),.error_flag(error_flag));

    always #5 clk=~clk;
    integer errors=0;

    initial begin
        clk=0;rst=1;init=0;in_a=0;in_b=0;in_data=0;in_valid=0;
        repeat(3) @(posedge clk); rst=0;
        // Load weight=5, then compute with in_a=3
        init=1; in_b=8'd5; in_a=0; in_valid=1; in_data=0;
        @(posedge clk); #1; init=0; in_a=8'd3;
        repeat(4) begin @(posedge clk); #1;
            if (error_flag) begin
                $display("FAIL: WS_DMR spurious error_flag in normal operation");
                errors=errors+1;
            end
        end
        $display("PASS: WS_DMR no error_flag in normal operation");

        // Fault injection: override pe_ws_B output
        force dut.pe_ws_B.out_data = 16'hFFFF;
        @(posedge clk); #1;
        if (error_flag)
            $display("PASS: WS_DMR error_flag raised on fault injection");
        else begin
            $display("FAIL: WS_DMR error_flag NOT raised");
            errors=errors+1;
        end
        release dut.pe_ws_B.out_data;

        if (errors==0) $display("PASS: pe_ws_dmr all tests");
        else           $display("FAIL: pe_ws_dmr %0d errors", errors);
        #20; $finish;
    end
    initial begin #3000; $display("FAIL: pe_ws_dmr TIMEOUT"); $finish; end
endmodule
