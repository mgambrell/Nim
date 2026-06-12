# KNOWN-FAILING repro module — cross-module distinct-of-managed-value ARC bug.
# See test_vow_arc_distinct_dep.nim (the importer) for the full story and the
# run line. This module compiles CLEAN standalone; the bug only fires when it
# is pulled in as a dependency. Pure stock-Nim syntax on purpose: stock 2.0.0
# / 2.2.0 / 2.2.8 all compile this fine, so it is an upstream DEVEL (2.3.x)
# regression, suitable for an upstream report as-is.
#
# Every line is load-bearing (verified by single-ingredient removal):
#   - Val must be a VALUE object VARIANT (a plain object doesn't trigger).
#   - Key must be `distinct Val`, used as a Table key.
#   - The recursion must go THROUGH the distinct:
#       Val -> Box(ref) -> Table[Key = distinct Val, Val].
#     (Dropping Box, or routing the recursion through a bare seq instead of
#     Table, loses the repro.)
#   - At least one of ==/hash must CONVERT the distinct back (Val(a)); with
#     fully trivial bodies it compiles.
#   - put's table-write must live HERE: the same statement written in the
#     importer compiles fine.
import std/[tables, hashes]

type
  Key* = distinct Val
  Box* = ref object
    t*: Table[Key, Val]
  Val* = object
    case b*: bool
    of false: discard
    of true: h*: Box

proc `==`*(a, b: Key): bool = Val(a).b == Val(b).b
proc hash*(k: Key): Hash = Hash(0)

proc put*(box: Box, v: Val) =
  # The lvalue-to-sink conversion `Key(v)` is where injectdestructors
  # notices the distinct type arrived without attached hooks.
  box.t[Key(v)] = v
