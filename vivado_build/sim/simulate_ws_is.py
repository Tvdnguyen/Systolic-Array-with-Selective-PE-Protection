#!/usr/bin/env python3
"""
simulate_ws_is.py
Cycle-accurate Python simulation of WS/IS systolic arrays.
Models every pipeline register in pe_ws.v, pe_is.v, mem_read_m0.sv,
mem_read_m1.sv, and the systolic counter/init generator — all with
non-blocking assignment semantics.

Verified to produce bit-exact match with Verilog/iverilog simulation.
"""

class CycleAccurateSim:
    """
    Simulates N×N systolic_ws or systolic_is with behavioral BRAM.

    bram_m0[r][k] = activation value
    bram_m1[c][k] = weight / input value

    pe_type: 'ws' or 'is'
    """
    def __init__(self, N, DW, bram_m0, bram_m1, pe_type='ws'):
        self.N = N
        self.DW = DW
        self.MASK = (1 << (2*DW)) - 1
        self.DWM  = (1 << DW) - 1
        self.bram_m0  = [row[:] for row in bram_m0]
        self.bram_m1  = [row[:] for row in bram_m1]
        self.pe_type  = pe_type
        self._reset()

    def _reset(self):
        N = self.N
        # Counters
        self.col_m0 = 0     # column_m0  (= row_m1 in counter_m1)
        # mem_read bank chains (N stages, stage 0 = immediate)
        self.chain_m0_addr = [0]*N   # delayed rd_addr for each bank
        self.chain_m0_en   = [0]*N
        self.chain_m1_addr = [0]*N
        self.chain_m1_en   = [0]*N
        # BRAM registered output (1-cycle latency)
        self.m0_out = [0]*N
        self.m1_out = [0]*N
        # Systolic init wavefront
        self.slice = 2*N - 1
        self.init_grid = [[0]*N for _ in range(N)]
        # PE state: pe[r][c] = dict with all registers
        self.pe = [[self._new_pe() for c in range(N)] for r in range(N)]
        # Horizontal wire (a_pipe out_a): ha[r][c] = pe[r][c].a_pipe
        self.ha = [[0]*N for _ in range(N)]
        # Vertical wire (b_pipe out_b): vb[r][c] = pe[r][c].b_pipe (for loading)
        self.vb = [[0]*N for _ in range(N)]
        # Output chain: psum
        # WS: flows RIGHT  → od[r][c] = out_data at the output of PE[r][c]
        # (od[r][N-1] = m2[r])
        self.od  = [[0]*N for _ in range(N)]
        self.ov  = [[0]*N for _ in range(N)]

    def _new_pe(self):
        return {
            # Common pass-through
            'a_pipe': 0, 'b_pipe': 0,
            # WS/IS specific
            'w_reg': 0, 'a_reg': 0,
            'product_r': 0,
            'in_data_r': 0, 'in_valid_r': 0, 'init_r': 0,
            'out_data': 0, 'out_valid': 0,
            # OS specific (pe.v registers)
            'out_tmp': 0, 'out_tmp_r': 0,
            'out_stage': 0, 'out_stagevalid': 0,
            'data_rsrv': 0,
            'in_a_r': 0, 'in_b_r': 0,
        }

    def tick(self, rst):
        """Simulate one rising clock edge. Returns list of (row, data) valid outputs."""
        N   = self.N
        M   = N
        DWM = self.DWM
        MASK= self.MASK

        # ── Snapshot OLD state (non-blocking semantics) ──────────────
        old_col      = self.col_m0
        old_c0a      = self.chain_m0_addr[:]
        old_c0e      = self.chain_m0_en[:]
        old_c1a      = self.chain_m1_addr[:]
        old_c1e      = self.chain_m1_en[:]
        old_m0       = self.m0_out[:]
        old_m1       = self.m1_out[:]
        old_slice    = self.slice
        old_init     = [[self.init_grid[r][c] for c in range(N)] for r in range(N)]
        old_pe       = [[dict(self.pe[r][c]) for c in range(N)] for r in range(N)]
        old_ha       = [[self.ha[r][c] for c in range(N)] for r in range(N)]
        old_vb       = [[self.vb[r][c] for c in range(N)] for r in range(N)]
        old_od       = [[self.od[r][c] for c in range(N)] for r in range(N)]
        old_ov       = [[self.ov[r][c] for c in range(N)] for r in range(N)]

        if rst:
            self._reset()
            return []

        outputs = []

        # ── Counter (column_m0 = row_m1) ────────────────────────────
        new_col = (old_col + 1) % M

        # ── Init wavefront ───────────────────────────────────────────
        new_init  = [[0]*N for _ in range(N)]
        new_slice = old_slice
        # If column wraps: slice <- 0 (but slice+1 wins if both trigger)
        new_slice_from_wrap = 0
        wrap_triggered = (old_col == M-1)
        new_slice_from_inc = old_slice + 1

        if old_slice < 2*N-1:
            for r in range(N):
                for c in range(N):
                    if r+c == old_slice:
                        new_init[r][c] = 1
            # slice+1 wins over slice-reset (later assignment in always block)
            new_slice = new_slice_from_inc
        elif wrap_triggered:
            new_slice = 0

        # ── mem_read_m0 bank chain ───────────────────────────────────
        addr0 = old_col           # address = column_m0 (for M=N: row=0, addr=col)
        new_c0a = [0]*N;  new_c0e = [0]*N
        new_c0a[0] = addr0;  new_c0e[0] = 1
        for r in range(1, N):
            new_c0a[r] = old_c0a[r-1]; new_c0e[r] = old_c0e[r-1]

        # ── mem_read_m1 bank chain ───────────────────────────────────
        addr1 = old_col           # row_m1 = column counter, same as col_m0
        new_c1a = [0]*N;  new_c1e = [0]*N
        new_c1a[0] = addr1;  new_c1e[0] = 1
        for c in range(1, N):
            new_c1a[c] = old_c1a[c-1]; new_c1e[c] = old_c1e[c-1]

        # ── BRAM registered read (uses CURRENT-CYCLE addresses) ──────
        # Verilog: rd_addr_bram[0] is combinational from col_m0 (same posedge),
        # so the BRAM samples the NEW address this tick, not the previous.
        new_m0 = [0]*N
        new_m1 = [0]*N
        for r in range(N):
            if new_c0e[r] and new_c0a[r] < N:
                new_m0[r] = self.bram_m0[r][new_c0a[r]] & DWM
        for c in range(N):
            if new_c1e[c] and new_c1a[c] < N:
                new_m1[c] = self.bram_m1[c][new_c1a[c]] & DWM

        # ── Compute PE inputs from horizontal/vertical wires ─────────
        # HorizontalWire[r][0] = old_m0[r];  [r][c] = old_ha[r][c-1].out_a
        # VerticalWire[0][c]   = old_m1[c];  [r][c] = old_vb[r-1][c].out_b
        in_a = [[0]*N for _ in range(N)]
        in_b = [[0]*N for _ in range(N)]
        for r in range(N):
            in_a[r][0] = old_m0[r]
        for c in range(N):
            in_b[0][c] = old_m1[c]
        for r in range(N):
            for c in range(1, N):
                in_a[r][c] = old_ha[r][c-1]   # out_a of left PE
        for r in range(1, N):
            for c in range(N):
                in_b[r][c] = old_vb[r-1][c]   # out_b of above PE

        # Boundary valid: OS=0, WS/IS=~rst=1
        in_data_pe  = [[0]*N for _ in range(N)]
        in_valid_pe = [[0]*N for _ in range(N)]
        for r in range(N):
            in_data_pe[r][0]  = 0
            in_valid_pe[r][0] = 1 if self.pe_type in ('ws','is') else 0
        for r in range(N):
            for c in range(1, N):
                in_data_pe[r][c]  = old_od[r][c-1]
                in_valid_pe[r][c] = old_ov[r][c-1]

        new_pe  = [[None]*N for _ in range(N)]
        new_ha  = [[0]*N for _ in range(N)]
        new_vb  = [[0]*N for _ in range(N)]
        new_od  = [[0]*N for _ in range(N)]
        new_ov  = [[0]*N for _ in range(N)]

        for r in range(N):
            for c in range(N):
                p      = old_pe[r][c]
                init_c = old_init[r][c]
                ia     = in_a[r][c]; ib = in_b[r][c]
                id_    = in_data_pe[r][c]; iv = in_valid_pe[r][c]
                n = {}
                n['a_pipe'] = ia & DWM
                n['b_pipe'] = ib & DWM

                if self.pe_type == 'os':
                    # pe.v exact register-transfer model
                    n['init_r']     = init_c
                    n['in_data_r']  = id_ & MASK
                    n['in_valid_r'] = iv
                    n['in_a_r']     = ia & DWM
                    n['in_b_r']     = ib & DWM
                    n['out_tmp_r']  = ((ia & DWM) * (ib & DWM)) & MASK
                    if p['init_r']:
                        n['out_tmp'] = p['out_tmp_r']
                    else:
                        n['out_tmp'] = (p['out_tmp'] + p['out_tmp_r']) & MASK
                    if p['init_r'] == 1 and p['in_valid_r'] == 1:
                        n['out_stage']      = p['in_data_r']
                        n['out_stagevalid'] = p['in_valid_r']
                        n['out_data']       = p['out_tmp']
                        n['out_valid']      = init_c
                        n['data_rsrv']      = 1
                    elif p['data_rsrv'] == 1:
                        n['out_data']  = p['out_stage']
                        n['out_valid'] = p['out_stagevalid']
                        if p['in_valid_r'] == 1:
                            n['data_rsrv']      = 1
                            n['out_stage']      = p['in_data_r']
                            n['out_stagevalid'] = p['in_valid_r']
                        else:
                            n['data_rsrv']      = 0
                            n['out_stage']      = p['out_stage']
                            n['out_stagevalid'] = p['out_stagevalid']
                    elif p['init_r'] == 1 and p['in_valid_r'] == 0:
                        n['out_data']       = p['out_tmp']
                        n['out_valid']      = p['init_r']
                        n['data_rsrv']      = p['data_rsrv']
                        n['out_stage']      = p['out_stage']
                        n['out_stagevalid'] = p['out_stagevalid']
                    else:
                        n['out_data']       = p['in_data_r']
                        n['out_valid']      = p['in_valid_r']
                        n['data_rsrv']      = p['data_rsrv']
                        n['out_stage']      = p['out_stage']
                        n['out_stagevalid'] = p['out_stagevalid']
                    n['w_reg']=0;n['a_reg']=0;n['product_r']=0

                elif self.pe_type == 'ws':
                    n['in_data_r']=id_&MASK; n['in_valid_r']=iv; n['init_r']=init_c
                    n['w_reg'] = (ib&DWM) if init_c else p['w_reg']
                    n['a_reg'] = 0
                    n['product_r'] = (ia&DWM)*p['w_reg']&MASK
                    if not p['init_r']:
                        n['out_data']=(p['in_data_r']+p['product_r'])&MASK; n['out_valid']=p['in_valid_r']
                    else:
                        n['out_data']=0; n['out_valid']=0
                    n['out_tmp']=0;n['out_tmp_r']=0;n['out_stage']=0
                    n['out_stagevalid']=0;n['data_rsrv']=0;n['in_a_r']=0;n['in_b_r']=0

                else:  # is
                    n['in_data_r']=id_&MASK; n['in_valid_r']=iv; n['init_r']=init_c
                    n['a_reg'] = (ia&DWM) if init_c else p.get('a_reg',0)
                    n['w_reg'] = 0
                    n['product_r'] = p.get('a_reg',0)*(ib&DWM)&MASK
                    if not p['init_r']:
                        n['out_data']=(p['in_data_r']+p['product_r'])&MASK; n['out_valid']=p['in_valid_r']
                    else:
                        n['out_data']=0; n['out_valid']=0
                    n['out_tmp']=0;n['out_tmp_r']=0;n['out_stage']=0
                    n['out_stagevalid']=0;n['data_rsrv']=0;n['in_a_r']=0;n['in_b_r']=0

                new_pe[r][c] = n
                new_ha[r][c] = n['a_pipe']
                new_vb[r][c] = n['b_pipe']
                new_od[r][c] = n['out_data']
                new_ov[r][c] = n['out_valid']

        # ── Collect outputs from rightmost column ────────────────────
        for r in range(N):
            d = new_od[r][N-1]; v = new_ov[r][N-1]
            if v and d != 0:
                outputs.append((r, d))

        # ── Commit all state ─────────────────────────────────────────
        self.col_m0          = new_col
        self.chain_m0_addr   = new_c0a
        self.chain_m0_en     = new_c0e
        self.chain_m1_addr   = new_c1a
        self.chain_m1_en     = new_c1e
        self.m0_out          = new_m0
        self.m1_out          = new_m1
        self.slice           = new_slice
        self.init_grid       = new_init
        self.pe              = new_pe
        self.ha              = new_ha
        self.vb              = new_vb
        self.od              = new_od
        self.ov              = new_ov

        return outputs

    def run(self, rst_cycles, run_cycles, max_per_row=None):
        """Run full simulation. Return collected outputs per row."""
        N = self.N
        if max_per_row is None:
            max_per_row = N
        result = {r: [] for r in range(N)}

        for _ in range(rst_cycles):
            self.tick(rst=True)
        for _ in range(run_cycles):
            outs = self.tick(rst=False)
            for (r, d) in outs:
                if len(result[r]) < max_per_row:
                    result[r].append(d)
        return result
