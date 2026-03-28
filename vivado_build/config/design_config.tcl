# ==============================================================
# design_config.tcl  —  User Configuration File
# Edit this file to configure your system before building.
# ==============================================================

# ── Systolic Array Dimension (NxN PEs) ─────────────────────────
# M is FIXED equal to N (M = N)
# For input matrices larger than NxN, the PS tiles automatically.
set DESIGN_N   4

# ── Data width per element (bits) ──────────────────────────────
set DESIGN_D_W 8

# ── Dataflow Strategy ──────────────────────────────────────────
# Choose one of:  OS | WS | IS
#
#  ┌───────────────┬──────────────────┬────────────────────────────────────────────────────┐
#  │ Dataflow      │ Stationary Data  │ Description                                        │
#  ├───────────────┼──────────────────┼────────────────────────────────────────────────────┤
#  │ OS (default)  │ Output (C psum)  │ Partial sums accumulate inside each PE.            │
#  │               │                  │ A flows right, B flows down, C stays in PE.        │
#  │               │                  │ Best for: layers where output reuse is high        │
#  │               │                  │ (e.g. large kernel convolutions).                  │
#  ├───────────────┼──────────────────┼────────────────────────────────────────────────────┤
#  │ WS            │ Weight (B)       │ Weights B are pre-loaded into PE registers once.   │
#  │               │                  │ A flows right, partial sums flow right via chain.  │
#  │               │                  │ C exits from rightmost column each compute cycle.  │
#  │               │                  │ Best for: FC layers, small kernels with large batch │
#  │               │                  │ (reuse weights across many input activations).      │
#  ├───────────────┼──────────────────┼────────────────────────────────────────────────────┤
#  │ IS            │ Input (A)        │ Inputs A are pre-loaded into PE registers once.    │
#  │               │                  │ B flows down, partial sums flow right via chain.   │
#  │               │                  │ C exits from rightmost column each compute cycle.  │
#  │               │                  │ Best for: Conv layers with large feature maps      │
#  │               │                  │ (reuse activations across multiple weight sets).   │
#  │               │                  │ NOTE: Computes A × B^T (B transpose). Pre-         │
#  │               │                  │ transpose B in software if A×B is needed.          │
#  └───────────────┴──────────────────┴────────────────────────────────────────────────────┘
#
# Changing this setting → regenerates systolic_protected.sv → rebuild bitstream.
set DESIGN_DATAFLOW "OS"

# ── PE Protection Map  ─────────────────────────────────────────
# Format:  { {row col mode} ... }
#   row, col : PE position in the NxN grid (0-indexed)
#   mode     : none | DMR | TMR
#
# Any (row,col) NOT listed defaults to "none" (unprotected).
#
# GUIDANCE (model-dependent — user decides):
#   TMR  →  PEs whose errors cause the highest classification loss
#            (typically early rows / columns; determined by NVF analysis)
#   DMR  →  PEs with moderate sensitivity (detects fault, raises flag)
#   none →  PEs with low sensitivity or where resource budget is tight
#
# This map is resolved at SYNTHESIS TIME → baked into the bitstream.
# Protection applies to the base PE type selected by DESIGN_DATAFLOW:
#   OS  → pe.v wrapped by pe_dmr.v / pe_tmr.v
#   WS  → pe_ws.v wrapped by pe_ws_dmr.v / pe_ws_tmr.v
#   IS  → pe_is.v wrapped by pe_is_dmr.v / pe_is_tmr.v
# ------------------------------------------------------------------
set PE_PROTECTION_MAP {
    {0 0 TMR}   {0 1 TMR}   {0 2 DMR}   {0 3 DMR}
    {1 0 TMR}   {1 1 DMR}   {1 2 none}  {1 3 none}
    {2 0 DMR}   {2 1 none}  {2 2 none}  {2 3 none}
    {3 0 none}  {3 1 none}  {3 2 none}  {3 3 none}
}
