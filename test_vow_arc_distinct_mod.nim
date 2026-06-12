# KNOWN-FAILING repro module — distinct-of-managed-value loses ARC hooks at a
# cross-module sink copy. See test_vow_arc_distinct_dep.nim (the importer) for
# the full story and run line. This module compiles CLEAN standalone; the bug
# only fires when it is pulled in as a dependency.
#
# This is the UNIVERSAL form: 11 lines, zero imports, crashes every compiler
# we tested — stock 2.0.0 / 2.2.0 / 2.2.8, upstream devel tip b44d373
# (2026-06-11), and this fork — under both --mm:arc and --mm:orc. The bug is
# ancient; what changed recently is EXPOSURE: upstream PR #24724 (482662d,
# 2025-03-23, "Table add missing sink") made Table/OrderedTable key params
# `sink`, so since then ordinary `t[Key(k)] = v` code over a
# Table[distinct V, V] hits the same path with no explicit `sink` anywhere
# (that Table form passes on <= 2.2.8 and crashes on devel — found by a
# 10-step git bisect, parent-verified).
#
# Every line is load-bearing (verified by single-ingredient removal):
#   - Key must be `distinct Val` where Val is a VALUE object with managed
#     content.
#   - The recursion must run THROUGH the distinct via BOTH the ref and the
#     seq: Val -> Box(ref) -> seq[Key = distinct Val]. Dropping the ref
#     (Val.s: seq[Key] directly) or replacing the seq with a bare `k: Key`
#     field each make it compile.
#   - The lvalue-to-sink conversion `sinkIt(Key(v))` must live HERE: the
#     same call written in the importer compiles fine.
#   - The importer must actually call put (a bare import compiles).
type
  Key* = distinct Val
  Box* = ref object
    s*: seq[Key]
  Val* = object
    h*: Box

proc sinkIt*(k: sink Key) = discard

proc put*(v: Val) =
  # `Key(v)` converts an lvalue and lands in injectdestructors'
  # passCopyToSink, where Key arrives with managed contents but no
  # attached =destroy -> assert (proper error since fork b22b532f4).
  sinkIt(Key(v))
