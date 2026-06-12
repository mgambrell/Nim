# REGRESSION TEST (fixed in this fork 2026-06-12; still OPEN upstream):
# lvalue-to-sink copy of a `distinct` over a recursive managed object.
# Must compile and print "ok". Pure stock Nim, no VOW syntax.
#
# Run:
#   bin/nim c -r --mm:arc test_vow_arc_distinct_dep.nim
#
# The bug (full history; see also the upstream issue draft kept in the
# mx_rata_test repo, junk/nim_upstream_issue_draft.md):
#   - pre-1.6 (1.2.18/1.4.8): distincts were hook-invisible; this shape
#     compiled but silently LEAKED the sink param (no =destroy emitted;
#     measured 48 B/iter).
#   - fc9cf2088 (#16730, 2021-01, shipped 1.6.0) made distincts hook-aware
#     but left a flag asymmetry: createTypeBoundOps attaches the real ops to
#     the CANONICAL type yet sets tfHasAsgn only on the `sink Key` wrapper;
#     a recursive re-entry (Val -> Box -> seq[Key]) additionally marks Key
#     tfCheckedForDestructor while its destructor is still an empty
#     #15122-style prototype. passCopyToSink then sees managed-but-hookless
#     and dies: `not containsManagedMemory(nTyp)` AssertionDefect
#     (1.6.14 through upstream devel b44d373, arc AND orc; proper located
#     error in this fork since b22b532f4).
#   - 482662d1 (#24724, 2025-03) made Table keys `sink`, exposing the ICE
#     to ordinary Table[distinct V, V] users.
#   - SECOND bug (since 2.0, still open upstream): the abandoned empty
#     prototype gets baked into setLen/reset[Key] generic instantiations ->
#     seq[distinct] elements silently never destroyed on shrink.
#
# The fork fix (liftdestructors.nim, ported from /tmp/nimfix work): set
# tfHasAsgn on canon as well as orig when the lifted destructor is
# non-trivial (ICE fix), and give an already-attached empty prototype a
# forwarding body to the borrowed base op in produceSymDistinctType
# (leak fix). Validated: upstream testament cat arc (132) + destructor (95)
# zero regressions on devel; test_vow.vow green; full vx VOW->C compile
# green; valgrind-clean sink stress.
#
# NOTE the dead-code trap that misled diagnosis: an UNCALLED put() is never
# destructor-injected, so a module containing this code compiles standalone
# and only crashed on first import-and-call. A single file that CALLS put
# (this file's shape collapsed) crashes unpatched compilers all the same.
# The two-file form is kept to document exactly that library trap.
import test_vow_arc_distinct_mod

put(Val())
echo "ok"
