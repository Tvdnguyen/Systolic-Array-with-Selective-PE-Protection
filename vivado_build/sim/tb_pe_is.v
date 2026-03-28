`timescale 1ns/1ps
// tb_pe_is.v — corrected: continuous monitor during compute+drain
// A=6, weights=[2,3,4,1], in_data=0
// Expected products: 6*2=12, 6*3=18, 6*4=24, 6*1=6

module tb_pe_is;
    parameter DW = 8;
    localparam A_VAL = 6;

    reg clk, rst, init, in_valid;
    reg [DW-1:0]    in_a, in_b;
    reg [2*DW-1:0]  in_data;
    wire [DW-1:0]   out_a, out_b;
    wire [2*DW-1:0] out_data;
    wire            out_valid;

    pe_is #(.D_W(DW),.i(0),.j(0)) dut (
        .clk(clk), .rst(rst), .init(init),
        .in_a(in_a), .in_b(in_b), .out_a(out_a), .out_b(out_b),
        .in_data(in_data), .in_valid(in_valid),
        .out_data(out_data), .out_valid(out_valid));

    always #5 clk = ~clk;
    integer idx = 0;

    always @(posedge clk) begin
        #2;
        if (!rst)
            $display("OUT cycle=%0d data=%0d valid=%0d", idx, out_data, out_valid);
        idx = idx + 1;
    end

    integer k;
    reg [DW-1:0] wts [0:3];

    initial begin
        clk=0; rst=1; init=0; in_a=0; in_b=0; in_data=0; in_valid=0;
        wts[0]=2; wts[1]=3; wts[2]=4; wts[3]=1;

        repeat(3) @(posedge clk); rst=0;

        // LOAD activation
        @(posedge clk); #1; init=1; in_a=A_VAL; in_b=0; in_valid=1; in_data=0;

        // COMPUTE: stream weights
        @(posedge clk); #1; init=0;
        for (k=0; k<4; k=k+1) begin
            in_b = wts[k]; in_a=0;
            @(posedge clk); #1;
        end

        // DRAIN
        in_b=0; in_valid=0;
        repeat(5) @(posedge clk);

        $display("PASS: pe_is output stream captured (compare with golden_model.py)");
        #20; $finish;
    end
    initial begin #5000; $display("FAIL: pe_is TIMEOUT"); $finish; end
endmodule
