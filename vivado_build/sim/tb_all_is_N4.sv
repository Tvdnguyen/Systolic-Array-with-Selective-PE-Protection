`timescale 1ns/1ps
module tb_all_is_N4;
localparam N=4, M=4, DW=8;
reg  clk=0, rst=1, enable_row_count_m0=0;
wire [$clog2(M)-1:0]   column_m0, row_m1;
wire [$clog2(M/N)-1:0] row_m0, column_m1;
reg [DW-1:0] bram_m0 [4][4];
reg [DW-1:0] bram_m1 [4][4];
reg [DW-1:0] m0_out [N-1:0]; reg [DW-1:0] m1_out [N-1:0];
wire [$clog2((M*M)/N)-1:0] rd_addr_m0 [N-1:0]; wire [N-1:0] rd_en_m0;
wire [$clog2((M*M)/N)-1:0] rd_addr_m1 [N-1:0]; wire [N-1:0] rd_en_m1;
mem_read_m0 #(.D_W(DW),.N(N),.M(M)) mr0(.clk(clk),.row(row_m0),.column(column_m0),.rd_en(~rst),.rd_addr_bram(rd_addr_m0),.rd_en_bram(rd_en_m0));
mem_read_m1 #(.D_W(DW),.N(N),.M(M)) mr1(.clk(clk),.row(row_m1),.column(column_m1),.rd_en(~rst),.rd_addr_bram(rd_addr_m1),.rd_en_bram(rd_en_m1));
integer br;
always @(posedge clk) begin
    for (br=0;br<N;br=br+1) begin
        m0_out[br] <= (rd_en_m0[br] && rd_addr_m0[br]<4) ? bram_m0[br][rd_addr_m0[br]] : 0;
        m1_out[br] <= (rd_en_m1[br] && rd_addr_m1[br]<4) ? bram_m1[br][rd_addr_m1[br]] : 0;
    end
end
wire [2*DW-1:0] m2 [N-1:0]; wire [N-1:0] valid_m2;
systolic_is #(.D_W(DW),.N(N),.M(M)) dut(.clk(clk),.rst(rst),.enable_row_count_m0(enable_row_count_m0),.column_m0(column_m0),.row_m0(row_m0),.column_m1(column_m1),.row_m1(row_m1),.m0(m0_out),.m1(m1_out),.m2(m2),.valid_m2(valid_m2));
integer mr; integer row_cnt [N-1:0]; integer done_cnt;
always @(posedge clk) begin
    #1; if (!rst)
        for (mr=0;mr<N;mr=mr+1)
            if (valid_m2[mr] && !$isunknown(m2[mr]) && m2[mr]!=0 && row_cnt[mr]<N) begin
                $display("RES row=%0d data=%0d", mr, m2[mr]);
                row_cnt[mr]=row_cnt[mr]+1;
                if (row_cnt[mr]==N) done_cnt=done_cnt+1;
            end
end
    initial begin
        bram_m0[0][0] = 1;
        bram_m0[0][1] = 2;
        bram_m0[0][2] = 2;
        bram_m0[0][3] = 3;
        bram_m0[1][0] = 5;
        bram_m0[1][1] = 4;
        bram_m0[1][2] = 4;
        bram_m0[1][3] = 4;
        bram_m0[2][0] = 2;
        bram_m0[2][1] = 1;
        bram_m0[2][2] = 5;
        bram_m0[2][3] = 2;
        bram_m0[3][0] = 3;
        bram_m0[3][1] = 4;
        bram_m0[3][2] = 5;
        bram_m0[3][3] = 1;
        bram_m1[0][0] = 2;
        bram_m1[0][1] = 5;
        bram_m1[0][2] = 5;
        bram_m1[0][3] = 2;
        bram_m1[1][0] = 4;
        bram_m1[1][1] = 3;
        bram_m1[1][2] = 4;
        bram_m1[1][3] = 1;
        bram_m1[2][0] = 3;
        bram_m1[2][1] = 4;
        bram_m1[2][2] = 3;
        bram_m1[2][3] = 2;
        bram_m1[3][0] = 5;
        bram_m1[3][1] = 2;
        bram_m1[3][2] = 5;
        bram_m1[3][3] = 2;
    end
initial begin
    done_cnt=0; for(mr=0;mr<N;mr=mr+1) row_cnt[mr]=0;
    repeat(6) @(posedge clk);
    rst=0; enable_row_count_m0=1;
    begin:wl integer tmo=16*N+20;
        while(done_cnt<N && tmo>0) begin @(posedge clk);#1;tmo=tmo-1;end
    end
    if(done_cnt<N) $display("TIMEOUT"); else $display("SIM_DONE");
    #20; $finish;
end
always #5 clk=~clk;
initial begin #(400*N*10); $display("HARD_TIMEOUT"); $finish; end
endmodule
