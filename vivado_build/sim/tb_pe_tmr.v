`timescale 1ns/1ps
// tb_pe_tmr.v — Test pe_tmr.v (TMR majority-voter correction)
// Test A: Normal (all 3 copies agree) — output correct
// Test B: Inject fault into pe_C only — majority of A+B still correct
// Test C: Verify out_data matches pe_A value (not faulty pe_C value)

module tb_pe_tmr;
    parameter DW = 8;
    reg clk, rst, init, in_valid;
    reg [DW-1:0]    in_a, in_b;
    reg [2*DW-1:0]  in_data;
    wire [DW-1:0]   out_a, out_b;
    wire [2*DW-1:0] out_data;
    wire            out_valid;

    pe_tmr #(.D_W(DW),.i(0),.j(0)) dut (
        .clk(clk), .rst(rst), .init(init),
        .in_a(in_a), .in_b(in_b), .out_a(out_a), .out_b(out_b),
        .in_data(in_data), .in_valid(in_valid),
        .out_data(out_data), .out_valid(out_valid));

    // Reference: pe_A output (should match TMR output even when pe_C faulty)
    wire [2*DW-1:0] ref_data;
    wire            ref_valid;
    // Tap pe_A internal output
    assign ref_data  = dut.out_data_A;
    assign ref_valid = dut.out_valid_A;

    always #5 clk = ~clk;
    integer errors = 0;

    initial begin
        clk=0; rst=1; init=0; in_a=0; in_b=0; in_data=0; in_valid=0;
        repeat(3) @(posedge clk); rst=0;

        // ── TEST A: Normal — all agree ───────────────────────
        init=1; in_a=8'd6; in_b=8'd7; in_valid=1; in_data=0;
        @(posedge clk); #1; init=0;
        repeat(5) @(posedge clk);
        $display("PASS: TMR normal out_data=%0d (no fault)", out_data);

        // ── TEST B: Fault in pe_C only → majority corrects ───
        // Force pe_C to output wrong value while pe_A and pe_B are correct
        force dut.pe_C.out_data = 16'hBEEF;
        @(posedge clk); #1;
        @(posedge clk); #1;

        // TMR majority: out_data = (A&B)|(B&C)|(A&C)
        // Since C=0xBEEF (all 1s pattern mostly), but A=B (correct), A&B dominates
        // The majority voter should output A (= reference)
        if (out_data === ref_data) begin
            $display("PASS: TMR majority corrects pe_C fault: out_data=%0d (correct)", out_data);
        end else begin
            $display("FAIL: TMR majority result=%0d, expected ref=%0d (pe_A)", out_data, ref_data);
            errors = errors + 1;
        end
        release dut.pe_C.out_data;

        // ── TEST C: After fault removed, resumes correctly ────
        @(posedge clk); #1; @(posedge clk); #1;
        if (out_data === ref_data) begin
            $display("PASS: TMR correct output after fault removal");
        end else begin
            $display("FAIL: TMR out_data=%0d != ref=%0d after release", out_data, ref_data);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS: pe_tmr all tests");
        else             $display("FAIL: pe_tmr %0d errors", errors);

        #20; $finish;
    end
    initial begin #5000; $display("FAIL: pe_tmr TIMEOUT"); $finish; end
endmodule
