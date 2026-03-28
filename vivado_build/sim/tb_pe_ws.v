`timescale 1ns/1ps
// tb_pe_ws.v — corrected: monitor output during BOTH compute and drain phases
// W=7, acts=[3,5,2,4], in_data=0
// Expected products (1-cycle pipeline delay after each activation):
//   During K1 posedge: 3*7=21
//   During K2 posedge: 5*7=35
//   During K3 posedge: 2*7=14
//   During DRAIN0:     4*7=28

module tb_pe_ws;
    parameter DW = 8;
    localparam W = 7;

    reg clk, rst, init, in_valid;
    reg [DW-1:0]    in_a, in_b;
    reg [2*DW-1:0]  in_data;
    wire [DW-1:0]   out_a, out_b;
    wire [2*DW-1:0] out_data;
    wire            out_valid;

    pe_ws #(.D_W(DW),.i(0),.j(0)) dut (
        .clk(clk), .rst(rst), .init(init),
        .in_a(in_a), .in_b(in_b), .out_a(out_a), .out_b(out_b),
        .in_data(in_data), .in_valid(in_valid),
        .out_data(out_data), .out_valid(out_valid));

    always #5 clk = ~clk;
    integer idx = 0;

    // Continuous monitor — captures every clock edge output
    always @(posedge clk) begin
        #2; // sample after settling
        if (!rst)
            $display("OUT cycle=%0d data=%0d valid=%0d", idx, out_data, out_valid);
        idx = idx + 1;
    end

    integer k;
    reg [DW-1:0] acts [0:3];

    initial begin
        clk=0; rst=1; init=0; in_a=0; in_b=0; in_data=0; in_valid=0;
        acts[0]=3; acts[1]=5; acts[2]=2; acts[3]=4;

        repeat(3) @(posedge clk); rst=0;

        // LOAD weight (visible at NEXT posedge after #1)
        @(posedge clk); #1; init=1; in_b=W; in_a=0; in_valid=1; in_data=0;

        // COMPUTE: init goes low, then stream activations
        @(posedge clk); #1; init=0;
        for (k=0; k<4; k=k+1) begin
            in_a = acts[k]; in_b=0;
            @(posedge clk); #1;
        end

        // DRAIN: clear inputs, let pipeline flush
        in_a=0; in_valid=0;
        repeat(5) @(posedge clk);

        $display("PASS: pe_ws output stream captured (compare with golden_model.py)");
        #20; $finish;
    end
    initial begin #5000; $display("FAIL: pe_ws TIMEOUT"); $finish; end
endmodule
