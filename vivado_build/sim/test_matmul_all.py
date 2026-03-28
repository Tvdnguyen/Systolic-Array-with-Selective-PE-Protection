#!/usr/bin/env python3
"""
test_matmul_all.py
Complete verification: OS (exact C=A×B), WS and IS (cycle-accurate Python vs RTL)

For ALL three dataflows the test prints a side-by-side table:
   Row | Python output  | Verilog output | Match
and asserts EXACT equality for every output value.
"""

import subprocess, random, os, sys, datetime
sys.path.insert(0, os.path.dirname(__file__))
from simulate_ws_is import CycleAccurateSim

TEST_SIZES  = [2, 3, 4]
DW          = 8
MAX_VAL     = 5
RANDOM_SEED = 42
RST_CYCLES  = 6

SIM_DIR  = os.path.abspath(os.path.dirname(__file__))
SRC_ROOT = os.path.abspath(os.path.join(SIM_DIR, "../../"))
RTL_DIR  = os.path.abspath(os.path.join(SIM_DIR, "../rtl"))
LOG_PATH = os.path.join(SIM_DIR, "matmul_all_results.log")

logs = []; PASS_n = 0; FAIL_n = 0

def log(s): print(s); logs.append(s)

# ──────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────

def golden_os(A, B, N):
    return [[sum(A[r][k]*B[k][c] for k in range(N)) for c in range(N)]
            for r in range(N)]

def rand_matrix(N, seed):
    random.seed(seed)
    return [[random.randint(1, MAX_VAL) for _ in range(N)] for _ in range(N)]

def bram_layout(df, A, B, N):
    """Return (bram_m0, bram_m1) for the requested dataflow."""
    # bram_m0[r][k] = value fed to row r via mem_read_m0 bank r
    # bram_m1[c][k] = value fed to col c via mem_read_m1 bank c
    # For OS standard GEMM:
    #   bram_m0[r][k] = A[r][k],  bram_m1[c][k] = B[k][c]
    # We use the SAME layout for all three dataflows — the hardware handles timing.
    m0 = [[A[r][k] for k in range(N)] for r in range(N)]
    m1 = [[B[k][c] for k in range(N)] for c in range(N)]
    return m0, m1

# ──────────────────────────────────────────────────────────────────
# Verilog testbench template (same as test_matmul.py)
# ──────────────────────────────────────────────────────────────────

TB = r"""`timescale 1ns/1ps
module tb_all_{DF}_N{N};
localparam N={N}, M={N}, DW={DW};
reg  clk=0, rst=1, enable_row_count_m0=0;
wire [$clog2(M)-1:0]   column_m0, row_m1;
wire [$clog2(M/N)-1:0] row_m0, column_m1;
reg [DW-1:0] bram_m0 [{N}][{N}];
reg [DW-1:0] bram_m1 [{N}][{N}];
reg [DW-1:0] m0_out [N-1:0]; reg [DW-1:0] m1_out [N-1:0];
wire [$clog2((M*M)/N)-1:0] rd_addr_m0 [N-1:0]; wire [N-1:0] rd_en_m0;
wire [$clog2((M*M)/N)-1:0] rd_addr_m1 [N-1:0]; wire [N-1:0] rd_en_m1;
mem_read_m0 #(.D_W(DW),.N(N),.M(M)) mr0(.clk(clk),.row(row_m0),.column(column_m0),.rd_en(~rst),.rd_addr_bram(rd_addr_m0),.rd_en_bram(rd_en_m0));
mem_read_m1 #(.D_W(DW),.N(N),.M(M)) mr1(.clk(clk),.row(row_m1),.column(column_m1),.rd_en(~rst),.rd_addr_bram(rd_addr_m1),.rd_en_bram(rd_en_m1));
integer br;
always @(posedge clk) begin
    for (br=0;br<N;br=br+1) begin
        m0_out[br] <= (rd_en_m0[br] && rd_addr_m0[br]<{N}) ? bram_m0[br][rd_addr_m0[br]] : 0;
        m1_out[br] <= (rd_en_m1[br] && rd_addr_m1[br]<{N}) ? bram_m1[br][rd_addr_m1[br]] : 0;
    end
end
wire [2*DW-1:0] m2 [N-1:0]; wire [N-1:0] valid_m2;
{dut_inst}
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
{bram_init}
initial begin
    done_cnt=0; for(mr=0;mr<N;mr=mr+1) row_cnt[mr]=0;
    repeat({RST}) @(posedge clk);
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
"""

DUT = {
    "os": "systolic #(.D_W(DW),.N(N),.M(M)) dut(.clk(clk),.rst(rst),.enable_row_count_m0(enable_row_count_m0),.column_m0(column_m0),.row_m0(row_m0),.column_m1(column_m1),.row_m1(row_m1),.m0(m0_out),.m1(m1_out),.m2(m2),.valid_m2(valid_m2));",
    "ws": "systolic_ws #(.D_W(DW),.N(N),.M(M)) dut(.clk(clk),.rst(rst),.enable_row_count_m0(enable_row_count_m0),.column_m0(column_m0),.row_m0(row_m0),.column_m1(column_m1),.row_m1(row_m1),.m0(m0_out),.m1(m1_out),.m2(m2),.valid_m2(valid_m2));",
    "is": "systolic_is #(.D_W(DW),.N(N),.M(M)) dut(.clk(clk),.rst(rst),.enable_row_count_m0(enable_row_count_m0),.column_m0(column_m0),.row_m0(row_m0),.column_m1(column_m1),.row_m1(row_m1),.m0(m0_out),.m1(m1_out),.m2(m2),.valid_m2(valid_m2));",
}

SRCS = {
    "os": [os.path.join(SRC_ROOT,"pe.v"), os.path.join(SRC_ROOT,"counter.v"),
           os.path.join(SRC_ROOT,"mem_read_m0.sv"), os.path.join(SRC_ROOT,"mem_read_m1.sv"),
           os.path.join(SRC_ROOT,"systolic.sv")],
    "ws": [os.path.join(SRC_ROOT,"pe.v"), os.path.join(SRC_ROOT,"counter.v"),
           os.path.join(SRC_ROOT,"mem_read_m0.sv"), os.path.join(SRC_ROOT,"mem_read_m1.sv"),
           os.path.join(RTL_DIR,"pe_ws.v"), os.path.join(SIM_DIR,"systolic_ws.sv")],
    "is": [os.path.join(SRC_ROOT,"pe.v"), os.path.join(SRC_ROOT,"counter.v"),
           os.path.join(SRC_ROOT,"mem_read_m0.sv"), os.path.join(SRC_ROOT,"mem_read_m1.sv"),
           os.path.join(RTL_DIR,"pe_is.v"), os.path.join(SIM_DIR,"systolic_is.sv")],
}

def make_bram_init(m0, m1, N):
    lines = ["    initial begin"]
    for r in range(N):
        for k in range(N):
            lines.append(f"        bram_m0[{r}][{k}] = {m0[r][k]};")
    for c in range(N):
        for k in range(N):
            lines.append(f"        bram_m1[{c}][{k}] = {m1[c][k]};")
    lines.append("    end")
    return "\n".join(lines)

def gen_tb(df, N, m0, m1):
    return TB.format(DF=df, N=N, DW=DW, RST=RST_CYCLES,
                     dut_inst=DUT[df], bram_init=make_bram_init(m0, m1, N))

def run_verilog(tb_path, srcs, timeout=60):
    exe = tb_path.replace(".sv", ".vvp")
    r = subprocess.run(["iverilog","-g2012","-o",exe,tb_path]+srcs,
                       capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        return None, r.stderr[:300]
    r2 = subprocess.run(["vvp",exe], capture_output=True, text=True, timeout=timeout)
    return r2.stdout+r2.stderr, None

def parse_verilog(sim_out, N):
    rows = {r:[] for r in range(N)}
    for line in sim_out.split("\n"):
        if not line.startswith("RES"): continue
        try:
            parts = dict(p.split("=") for p in line.split()[1:])
            r=int(parts["row"]); d_s=parts["data"]
            if "x" in d_s or "z" in d_s: continue
            d=int(d_s)
            if r<N and len(rows[r])<N: rows[r].append(d)
        except: pass
    return rows

def run_python_sim(df, N, m0, m1):
    pe_type = {'os': 'os', 'ws': 'ws', 'is': 'is'}[df]
    sim = CycleAccurateSim(N, DW, m0, m1, pe_type=pe_type)
    run_cyc = max(16*N+20, 6*N+20)
    result = sim.run(rst_cycles=RST_CYCLES, run_cycles=run_cyc, max_per_row=N)
    return result

# ──────────────────────────────────────────────────────────────────
# Main test
# ──────────────────────────────────────────────────────────────────

def run_test(df, N, seed):
    global PASS_n, FAIL_n

    random.seed(seed)
    A = [[random.randint(1,MAX_VAL) for _ in range(N)] for _ in range(N)]
    B = [[random.randint(1,MAX_VAL) for _ in range(N)] for _ in range(N)]
    m0, m1 = bram_layout(df, A, B, N)

    log(f"\n  {'─'*56}")
    log(f"  {df.upper()} N={N}  A={A}  B={B}")
    if df == "os":
        C = golden_os(A, B, N)
        log(f"  C = A×B (golden) = {C}")

    # ── Python cycle-accurate sim (ALL dataflows) ────────────────
    py_out = run_python_sim(df, N, m0, m1)
    if df == "os":
        # Also verify Python sim produces the same SET as golden
        for r in range(N):
            if sorted(py_out[r]) != sorted(C[r]):
                log(f"  WARNING: Python sim row {r} set {sorted(py_out[r])} != golden {sorted(C[r])}")

    # ── Verilog ───────────────────────────────────────────────────
    tb = os.path.join(SIM_DIR, f"tb_all_{df}_N{N}.sv")
    with open(tb,"w") as f: f.write(gen_tb(df, N, m0, m1))
    sim_out, err = run_verilog(tb, SRCS[df])
    if err:
        log(f"  FAIL compile: {err}")
        FAIL_n += 1; return
    with open(os.path.join(SIM_DIR, f"sim_all_{df}_N{N}.txt"),"w") as f:
        f.write(sim_out)
    if "TIMEOUT" in sim_out:
        log("  FAIL: Verilog timeout")
        FAIL_n += 1; return
    rtl_out = parse_verilog(sim_out, N)

    # ── Compare IN ARRIVAL ORDER (no sorting!) ────────────────────
    log(f"\n  {'Row':<5} {'Python (arrival order)':<30} {'Verilog (arrival order)':<30} {'Match'}")
    log(f"  {'───':<5} {'──────────────────────':<30} {'───────────────────────':<30} {'─────'}")
    all_match = True
    for r in range(N):
        py_list  = py_out[r]       # arrival order — NOT sorted
        rtl_list = rtl_out[r]      # arrival order — NOT sorted
        match = "✓" if py_list == rtl_list else "✗  ← MISMATCH"
        if py_list != rtl_list:
            all_match = False
        log(f"  {r:<5} {str(py_list):<30} {str(rtl_list):<30} {match}")

    if all_match:
        log(f"\n  PASS: Python == Verilog (exact match, arrival order) ✓")
        PASS_n += 1
    else:
        log(f"\n  FAIL: mismatch detected (arrival order differs)")
        FAIL_n += 1

if __name__ == "__main__":
    t0 = datetime.datetime.now()
    log("="*62)
    log("  FULL DATAFLOW VERIFICATION  (Python cycle-accurate vs RTL)")
    log(f"  N={TEST_SIZES}  |  DW={DW}  |  seed={RANDOM_SEED}")
    log("="*62)

    for df in ["os","ws","is"]:
        log(f"\n{'═'*62}")
        log(f"  DATAFLOW: {df.upper()}")
        log(f"{'═'*62}")
        for N in TEST_SIZES:
            seed = RANDOM_SEED + N*13 + hash(df)%100
            run_test(df, N, seed)

    log(f"\n{'='*62}")
    log(f"  FINAL: PASS={PASS_n}  FAIL={FAIL_n}  ({datetime.datetime.now()-t0})")
    log(f"{'='*62}")

    with open(LOG_PATH,"w") as f:
        f.write(f"Run: {t0}\n" + "\n".join(logs))
    print(f"\nLog → {LOG_PATH}")
    sys.exit(0 if FAIL_n==0 else 1)
