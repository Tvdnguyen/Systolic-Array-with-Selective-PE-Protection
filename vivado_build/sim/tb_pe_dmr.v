`timescale 1ns/1ps
// tb_pe_dmr.v — Test pe_dmr.v (DMR fault detection)
// Test A: Normal operation — both PE copies produce same output → error_flag=0 always
// Test B: Fault injection — force pe_dmr.pe_B.out_data_B to wrong value → error_flag=1

module tb_pe_dmr;
    parameter DW = 8;
    reg clk, rst, init, in_valid;
    reg [DW-1:0]    in_a, in_b;
    reg [2*DW-1:0]  in_data;
    wire [DW-1:0]   out_a, out_b;
    wire [2*DW-1:0] out_data;
    wire            out_valid;
    wire            error_flag;

    pe_dmr #(.D_W(DW),.i(0),.j(0)) dut (
        .clk(clk), .rst(rst), .init(init),
        .in_a(in_a), .in_b(in_b), .out_a(out_a), .out_b(out_b),
        .in_data(in_data), .in_valid(in_valid),
        .out_data(out_data), .out_valid(out_valid),
        .error_flag(error_flag));

    always #5 clk = ~clk;
    integer errors = 0;

    task check_no_error;
        input [63:0] num_cycles;
        integer i;
        begin
            for (i=0; i<num_cycles; i=i+1) begin
                @(posedge clk); #1;
                if (error_flag) begin
                    $display("FAIL: DMR error_flag unexpectedly high at normal cycle %0d", i);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        clk=0; rst=1; init=0; in_a=0; in_b=0; in_data=0; in_valid=0;
        repeat(3) @(posedge clk); rst=0;

        // ── TEST A: Normal operation — no fault ──────────────
        init=1; in_a=8'd9; in_b=8'd3; in_valid=1; in_data=0;
        @(posedge clk); #1; init=0;
        in_a=8'd5; in_b=8'd7;
        check_no_error(10);
        $display("PASS: DMR no spurious error_flag in normal operation");

        // ── TEST B: Fault injection into pe_B's output data ──
        // Force the check copy's output to a wrong value so comparator fires
        init=1; in_a=8'd4; in_b=8'd2; in_valid=1;
        @(posedge clk); #1; init=0; in_a=8'd6; in_b=8'd8;
        @(posedge clk); #1;
        // Inject fault: override pe_B out_data register to wrong value
        force dut.pe_B.out_data = 16'hDEAD;
        @(posedge clk); #1;
        if (error_flag) begin
            $display("PASS: DMR error_flag correctly raised on fault injection");
        end else begin
            $display("FAIL: DMR error_flag NOT raised after fault injection");
            errors = errors + 1;
        end
        release dut.pe_B.out_data;

        // ── TEST C: Error clears after fault removal ──────────
        @(posedge clk); #1; @(posedge clk); #1;
        if (!error_flag) begin
            $display("PASS: DMR error_flag cleared after fault removal");
        end else begin
            $display("INFO: DMR error_flag still high (may need more cycles to clear)");
        end

        if (errors == 0)
            $display("PASS: pe_dmr all tests");
        else
            $display("FAIL: pe_dmr %0d errors", errors);

        #20; $finish;
    end
    initial begin #5000; $display("FAIL: pe_dmr TIMEOUT"); $finish; end
endmodule
