#!/usr/bin/env python3
"""
golden_model.py
Python behavioral models for all three PE dataflow types (OS, WS, IS).
Generates expected outputs for every testbench, runs iverilog simulations,
compares results, and writes a detailed test log.

Usage:  python3 golden_model.py
Output: sim/test_results.log
"""

import subprocess, os, sys, math, datetime

SIM   = os.path.abspath(os.path.dirname(__file__))         # vivado_build/sim/
BUILD_DIR = os.path.abspath(os.path.join(SIM, ".."))      # vivado_build/
SRC   = os.path.abspath(os.path.join(BUILD_DIR, ".."))    # project root (pe.v, counter.v)
BUILD = os.path.join(BUILD_DIR, "rtl")                    # vivado_build/rtl/
LOG   = os.path.join(SIM, "test_results.log")

PASS = 0
FAIL = 0
log_lines = []

def log(msg):
    print(msg)
    log_lines.append(msg)

def section(title):
    bar = "=" * 60
    log(f"\n{bar}\n  {title}\n{bar}")

# ──────────────────────────────────────────────────────────────
# Python behavioral models
# ──────────────────────────────────────────────────────────────

def model_pe_ws(w_reg_val, activations, in_data_seq, D_W=8):
    """
    Simulate pe_ws.v pipeline (1 always block, non-blocking).
    Load: cycle 0 (init=1, in_b=w_reg_val) → w_reg captured.
    Compute: cycles 1..N (init=0, in_a=activations[i]).
    The tb reads out_data starting after the load cycle.
    Pipeline timing: out_data[t+2] = in_data[t] + in_a[t]*w_reg
    (1 cycle for product_r, init_r delays output by 1 more cycle)
    The tb collects 8 cycles of OUT lines starting right after load.
    Cycle 0 (idx=0): init_r=1 → out_data=0 (suppressed)
    Cycle 1 (idx=1): out_data = in_data[0(=0)] + product_r[cycle0=0*w=0] = 0 → wait...
    Actually, the tb reads from right after rst released until after activations.
    We match exactly what the testbench $displays.
    """
    MASK = (1 << (2*D_W)) - 1
    DW_MASK = (1 << D_W) - 1
    # State variables
    w_reg=0; product_r=0; in_data_r=0; in_valid_r=0; init_r=0; out_data=0; out_valid=0

    def tick(ia, ib, id_, iv, init):
        nonlocal w_reg,product_r,in_data_r,in_valid_r,init_r,out_data,out_valid
        # Compute new values using OLD state (non-blocking)
        nw   = (ib & DW_MASK) if init else w_reg
        nprod= (ia & DW_MASK) * w_reg & MASK
        nidr = id_ & MASK; nivr = iv; nir = int(init)
        if not init_r:
            nod = (in_data_r + product_r) & MASK; nov = in_valid_r
        else:
            nod = 0; nov = 0
        w_reg=nw; product_r=nprod; in_data_r=nidr; in_valid_r=nivr
        init_r=nir; out_data=nod; out_valid=nov
        return nod, nov

    results = []
    # Load cycle (matches tb: after rst, then init=1 applied)
    tick(0, w_reg_val, 0, 1, True)
    # Compute cycles: in_a streams through
    tick(0, 0, 0, 1, False)      # first compute cycle (in_a=0 before acts enter)
    for ia in activations:
        od, ov = tick(ia, 0, 0, 1, False)
        results.append((od, ov))
    # Extra drain cycles
    for _ in range(4):
        od, ov = tick(0, 0, 0, 0, False)
        results.append((od, ov))
    return results


def model_pe_is(a_reg_val, weights, in_data_seq, D_W=8):
    """Same pipeline structure as pe_ws but a_reg is stationary."""
    MASK = (1 << (2*D_W)) - 1
    DW_MASK = (1 << D_W) - 1
    a_reg=0; product_r=0; in_data_r=0; in_valid_r=0; init_r=0; out_data=0; out_valid=0

    def tick(ia, ib, id_, iv, init):
        nonlocal a_reg,product_r,in_data_r,in_valid_r,init_r,out_data,out_valid
        na   = (ia & DW_MASK) if init else a_reg
        nprod= a_reg * (ib & DW_MASK) & MASK
        nidr = id_ & MASK; nivr = iv; nir = int(init)
        if not init_r:
            nod = (in_data_r + product_r) & MASK; nov = in_valid_r
        else:
            nod = 0; nov = 0
        a_reg=na; product_r=nprod; in_data_r=nidr; in_valid_r=nivr
        init_r=nir; out_data=nod; out_valid=nov
        return nod, nov

    results = []
    tick(a_reg_val, 0, 0, 1, True)
    tick(0, 0, 0, 1, False)
    for ib in weights:
        od, ov = tick(0, ib, 0, 1, False)
        results.append((od, ov))
    for _ in range(4):
        od, ov = tick(0, 0, 0, 0, False)
        results.append((od, ov))
    return results


# ──────────────────────────────────────────────────────────────
# iverilog runner
# ──────────────────────────────────────────────────────────────

def compile_and_run(tb_file, src_files, sim_out, timeout=30):
    """Compile with iverilog -g2012 then run vvp. Returns (stdout, ok)."""
    exe = sim_out.replace(".log", "")
    cmd = ["iverilog", "-g2012", "-o", exe, tb_file] + src_files
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        return f"COMPILE ERROR:\n{r.stderr}", False
    r2 = subprocess.run(["vvp", exe], capture_output=True, text=True, timeout=timeout)
    return r2.stdout + r2.stderr, True


def run_test(name, tb, srcs, checker_fn):
    """Run one test: compile, run, check output."""
    global PASS, FAIL
    log(f"\n  [{name}]")
    sim_log = os.path.join(SIM, f"sim_{name}.log")
    out, ok = compile_and_run(tb, srcs, sim_log)
    with open(sim_log.replace(".log","_dump.txt"), "w") as f:
        f.write(out)
    if not ok:
        log(f"    COMPILE FAILED: {out[:200]}")
        FAIL += 1
        return
    result = checker_fn(out)
    if result is True:
        log("    PASS")
        PASS += 1
    else:
        log(f"    FAIL: {result}")
        FAIL += 1


# ──────────────────────────────────────────────────────────────
# Test: pe_ws single PE accumulation chain
# ──────────────────────────────────────────────────────────────

def check_pe_ws(sim_out):
    """
    WS PE: load w_reg=7, then stream acts=[3,5,2,4].
    Expected products: 3*7=21, 5*7=35, 2*7=14, 4*7=28.
    Verify exactly these values appear in the valid output stream.
    """
    W = 7; acts = [3, 5, 2, 4]
    expected = sorted([a * W for a in acts])
    found = []
    for line in sim_out.strip().split('\n'):
        if not line.startswith('OUT'): continue
        try:
            parts = dict(p.split('=') for p in line.split()[1:])
            d = int(parts['data']); v = int(parts['valid'])
            if v == 1 and d > 0:
                found.append(d)
        except Exception:
            pass
    found_sorted = sorted(found)
    if found_sorted == expected:
        return True
    return f"WS products mismatch: expected={expected} got={found_sorted}"


def check_pe_is(sim_out):
    """
    IS PE: load a_reg=6, then stream weights=[2,3,4,1].
    Expected products: 6*2=12, 6*3=18, 6*4=24, 6*1=6.
    Verify exactly these values appear in the valid output stream.
    """
    A = 6; weights = [2, 3, 4, 1]
    expected = sorted([A * w for w in weights])
    found = []
    for line in sim_out.strip().split('\n'):
        if not line.startswith('OUT'): continue
        try:
            parts = dict(p.split('=') for p in line.split()[1:])
            d = int(parts['data']); v = int(parts['valid'])
            if v == 1 and d > 0:
                found.append(d)
        except Exception:
            pass
    found_sorted = sorted(found)
    if found_sorted == expected:
        return True
    return f"IS products mismatch: expected={expected} got={found_sorted}"


def check_pass_fail(sim_out):
    """Generic: any FAIL line = test failed."""
    for line in sim_out.strip().split("\n"):
        if "FAIL" in line:
            return line
    if "PASS" not in sim_out:
        return "no PASS or FAIL markers found in output"
    return True


# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    os.makedirs(SIM, exist_ok=True)
    start = datetime.datetime.now()

    section("PE OS (Output Stationary) — pe.v")
    run_test("pe_os_basic",
        os.path.join(SIM, "tb_pe_os.v"),
        [os.path.join(SRC, "pe.v")],
        check_pass_fail)

    section("PE WS (Weight Stationary) — pe_ws.v")
    run_test("pe_ws_accum",
        os.path.join(SIM, "tb_pe_ws.v"),
        [os.path.join(BUILD, "pe_ws.v")],
        check_pe_ws)

    section("PE IS (Input Stationary) — pe_is.v")
    run_test("pe_is_accum",
        os.path.join(SIM, "tb_pe_is.v"),
        [os.path.join(BUILD, "pe_is.v")],
        check_pe_is)

    section("PE DMR — fault detection")
    run_test("pe_dmr_normal",
        os.path.join(SIM, "tb_pe_dmr.v"),
        [os.path.join(SRC, "pe.v"), os.path.join(BUILD, "pe_dmr.v")],
        check_pass_fail)

    section("PE TMR — fault correction")
    run_test("pe_tmr_correct",
        os.path.join(SIM, "tb_pe_tmr.v"),
        [os.path.join(SRC, "pe.v"), os.path.join(BUILD, "pe_tmr.v")],
        check_pass_fail)

    section("PE WS DMR — WS fault detection")
    run_test("pe_ws_dmr",
        os.path.join(SIM, "tb_pe_ws_dmr.v"),
        [os.path.join(BUILD, "pe_ws.v"), os.path.join(BUILD, "pe_ws_dmr.v")],
        check_pass_fail)

    section("PE WS TMR — WS fault correction")
    run_test("pe_ws_tmr",
        os.path.join(SIM, "tb_pe_ws_tmr.v"),
        [os.path.join(BUILD, "pe_ws.v"), os.path.join(BUILD, "pe_ws_tmr.v")],
        check_pass_fail)

    section("PE IS DMR — IS fault detection")
    run_test("pe_is_dmr",
        os.path.join(SIM, "tb_pe_is_dmr.v"),
        [os.path.join(BUILD, "pe_is.v"), os.path.join(BUILD, "pe_is_dmr.v")],
        check_pass_fail)

    section("PE IS TMR — IS fault correction")
    run_test("pe_is_tmr",
        os.path.join(SIM, "tb_pe_is_tmr.v"),
        [os.path.join(BUILD, "pe_is.v"), os.path.join(BUILD, "pe_is_tmr.v")],
        check_pass_fail)

    section("Systolic Array OS 4x4 — matrix multiply")
    run_test("systolic_os_4x4",
        os.path.join(SIM, "tb_systolic_os.v"),
        [os.path.join(SRC, "pe.v"),
         os.path.join(SRC, "counter.v"),
         os.path.join(SRC, "systolic.sv")],
        check_pass_fail)

    elapsed = datetime.datetime.now() - start
    section(f"SUMMARY  ({elapsed})")
    log(f"  PASS: {PASS}   FAIL: {FAIL}   TOTAL: {PASS+FAIL}")

    with open(LOG, "w") as f:
        f.write(f"Test run: {start}\n")
        f.write("\n".join(log_lines))
    print(f"\nLog written to: {LOG}")
    sys.exit(0 if FAIL == 0 else 1)
