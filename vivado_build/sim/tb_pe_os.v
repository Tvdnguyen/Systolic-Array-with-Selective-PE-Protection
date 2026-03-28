`timescale 1ns/1ps
// tb_pe_os.v — Test pe.v (Output Stationary PE)
// Tests:
//  A) Single MAC:  init=1→A=3,B=4 → 1 cycle accumulate → expect partial_sum=12 at output
//  B) Multi-cycle: 4 MACs accumulate → sum = 3*4+5*2+7*1+2*6 = 12+10+7+12 = 41
//  C) Pass-through: out_a = in_a (1 cycle delay), out_b = in_b (1 cycle delay)

module tb_pe_os;
    parameter DW = 8;
    reg clk, rst, init, in_valid;
    reg [DW-1:0]   in_a, in_b;
    reg [2*DW-1:0] in_data;
    wire [DW-1:0]  out_a, out_b;
    wire [2*DW-1:0] out_data;
    wire out_valid;

    pe #(.D_W(DW),.i(0),.j(0)) dut (
        .clk(clk), .rst(rst), .init(init),
        .in_a(in_a), .in_b(in_b), .out_a(out_a), .out_b(out_b),
        .in_data(in_data), .in_valid(in_valid),
        .out_data(out_data), .out_valid(out_valid));

    always #5 clk = ~clk;

    integer errors = 0;
    integer i;
    reg [2*DW-1:0] expected_sum;
    reg [DW-1:0]   prev_a, prev_b;

    // Test data: [in_a, in_b] pairs for multi-MAC test
    reg [DW-1:0] test_a [0:3];
    reg [DW-1:0] test_b [0:3];

    initial begin
        clk=0; rst=1; init=0; in_valid=0; in_a=0; in_b=0; in_data=0;
        test_a[0]=8'd3; test_a[1]=8'd5; test_a[2]=8'd7; test_a[3]=8'd2;
        test_b[0]=8'd4; test_b[1]=8'd2; test_b[2]=8'd1; test_b[3]=8'd6;
        // expected = 3*4+5*2+7*1+2*6 = 12+10+7+12 = 41
        expected_sum = 41;

        repeat(3) @(posedge clk);
        rst = 0;

        // ── TEST A: pass-through check ──────────────────────
        @(posedge clk); #1;
        in_a=8'd99; in_b=8'd55; init=0; in_valid=0;
        @(posedge clk); #1;
        prev_a = out_a; prev_b = out_b;
        @(posedge clk); #1;
        // out_a/out_b should reflect what was applied 1 clk ago
        if (prev_a !== 8'd99) begin
            $display("FAIL: pass-through out_a expected=99 got=%0d", prev_a);
            errors = errors + 1;
        end
        if (prev_b !== 8'd55) begin
            $display("FAIL: pass-through out_b expected=55 got=%0d", prev_b);
            errors = errors + 1;
        end

        // ── TEST B: Multi-MAC accumulation ──────────────────
        // Reset, then start with init=1 for first pair, init=0 for rest
        rst=1; @(posedge clk); #1; rst=0;
        in_data=0; in_valid=1;

        // init=1 for first element: start new accumulation
        init=1; in_a=test_a[0]; in_b=test_b[0];
        @(posedge clk); #1;
        init=0;
        for (i=1; i<4; i=i+1) begin
            in_a=test_a[i]; in_b=test_b[i];
            @(posedge clk); #1;
        end
        // Now assert init again to flush and check output
        init=1; in_a=0; in_b=0;
        @(posedge clk); #1;
        // out_data should carry accumulated result at next cycle
        @(posedge clk); #1;
        init=0;

        // Wait for out_valid
        begin : wait_valid
            integer timeout;
            timeout = 50;
            while (!out_valid && timeout > 0) begin
                @(posedge clk); #1;
                timeout = timeout - 1;
            end
        end

        if (out_valid && out_data == expected_sum) begin
            $display("PASS: pe_os multi-MAC sum=%0d", out_data);
        end else if (out_valid) begin
            $display("FAIL: pe_os multi-MAC expected=%0d got=%0d", expected_sum, out_data);
            errors = errors + 1;
        end else begin
            $display("FAIL: pe_os out_valid never asserted within timeout");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: pe_os all tests");
        else
            $display("FAIL: pe_os %0d errors", errors);

        #20; $finish;
    end

    initial begin
        #5000;
        $display("FAIL: pe_os TIMEOUT");
        $finish;
    end
endmodule
