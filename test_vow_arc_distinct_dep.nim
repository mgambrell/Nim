# KNOWN-FAILING (2026-06-12): cross-module `distinct` of a managed VALUE
# variant loses its lifted ARC hooks. NOT wired into test_vow.vow — this file
# documents an OPEN compiler bug; it becomes a real regression test the day
# the bug is fixed. The whole repro is 16 + 2 lines of PURE STOCK NIM (no VOW
# syntax) — see test_vow_arc_distinct_mod.nim for the ingredient list.
#
# Run:
#   bin/nim c -r --mm:arc test_vow_arc_distinct_dep.nim
#
# Behavior matrix (all verified 2026-06-12):
#   - stock nim 2.0.0 / 2.2.0 / 2.2.8:        compiles, prints ok
#       -> upstream 2.3.x DEVEL regression, NOT an MBG-introduced bug
#          (git history of liftdestructors/injectdestructors/modulegraphs in
#          this fork is purely upstream merges; suspicion: the IC refactor
#          line, #25282/#25344/#25427, which moved attached-op bookkeeping)
#   - this fork, module compiled STANDALONE:   compiles clean (the trap)
#   - this fork, pre-b22b532f4 binary:         compiler CRASH —
#       injectdestructors.nim(499) `not containsManagedMemory(nTyp)` assert
#   - this fork, source >= b22b532f4:          proper error at put() —
#       "passCopyToSink: type 'Key' contains managed memory but has no
#        attached =destroy"
#   - FIXED compiler:                          prints "ok", exit 0
#
# Mechanism (diagnosed, not fixed): attached ops live in the ModuleGraph
# keyed by PType itemId; sem only borrows base-type ops onto a distinct via
# produceSymDistinctType when createTypeBoundOps reaches it, and for this
# recursive-through-the-distinct shape the distinct's PType instance reaches
# injectdestructors' passCopyToSink with no ops attached — but only when the
# defining module is compiled as a dependency AND the proc is actually called
# by the importer. Workaround used in rbtranstest's rbvalue.vow: a plain
# wrapper `object` (field v: RbValue) instead of `distinct` — real objects
# always get hooks lifted; identical layout, zero runtime cost.
#
# No matching upstream issue found as of 2026-06-12 (#19250 is the same
# assert from an unrelated closure-in-seq trigger) — worth reporting.
import test_vow_arc_distinct_mod

put(Box(), Val())
echo "ok"
