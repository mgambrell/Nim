# KNOWN-FAILING (2026-06-12): `distinct` of a managed VALUE object loses its
# lifted ARC hooks at a cross-module lvalue-to-sink copy. NOT wired into
# test_vow.vow — this documents an OPEN compiler bug; it becomes a real
# regression test the day the bug is fixed. Pure stock Nim (no VOW syntax),
# 11 + 2 lines, zero imports — see test_vow_arc_distinct_mod.nim for the
# ingredient list.
#
# Run:
#   bin/nim c -r --mm:arc test_vow_arc_distinct_dep.nim
#
# Behavior matrix (verified 2026-06-12):
#   - stock 1.2.18 / 1.4.8 (--gc:arc):         compiles but SILENTLY LEAKS —
#       sink Key param body has no =destroy (48 B/iter, 9.6 MB / 200k calls;
#       non-distinct control destroys properly). Pre-1.6 distincts were
#       hook-invisible (Key(v) erased by transformConv), so "passing" there
#       is the miscompile, not correctness.
#   - stock 1.6.14 / 2.0.0 / 2.2.0 / 2.2.8:    ASSERT-CRASH — the leak became
#       an ICE at fc9cf2088 ("Fix 16722" #16730, 2021-01-15, shipped 1.6.0),
#       which made distincts hook-aware in transf/liftdestructors without
#       teaching injectdestructors to resolve hooks for IMPORTED distinct
#       instances (bisected over 1824 commits, 11 steps, 0 skips,
#       parent 52cf72800 re-verified).
#   - upstream devel tip b44d373 (2026-06-11): ASSERT-CRASH (arc AND orc)
#   - this fork pre-b22b532f4:                 ASSERT-CRASH
#       injectdestructors `not containsManagedMemory(nTyp)` (line 467 stock,
#       499 fork)
#   - this fork source >= b22b532f4:           proper error at put() —
#       "passCopyToSink: type 'Key' contains managed memory but has no
#        attached =destroy"
#   - module compiled STANDALONE, any compiler: clean (the trap: a library's
#       own tests pass; the first importer dies)
#   - FIXED compiler:                           prints "ok", exit 0
#
# History of the diagnosis: the bug originally surfaced here through
# rbtranstest's rbvalue.vow (RbHashKey = distinct RbValue) with NO explicit
# `sink` anywhere — via std Table. That Table-mediated form is a devel-only
# regression: a verified 10-step git bisect landed on upstream 482662d
# (PR #24724, 2025-03-23) which made Table key params `sink`, EXPOSING this
# much older compiler bug to ordinary Table[distinct V, V] users. With an
# explicit `sink` param (this file's form) the crash reproduces on every
# version back to 2.0.0.
#
# Mechanism (diagnosed, not fixed): attached ops are keyed by PType itemId in
# the ModuleGraph; hook lifting for a distinct (produceSymDistinctType
# borrowing the base type's ops) never runs for this
# recursive-through-the-distinct shape when the defining module is compiled
# as a dependency, so the distinct's PType instance reaches passCopyToSink
# with no ops attached. Workaround used in rbtranstest's rbvalue.vow: a plain
# wrapper `object` (field v: RbValue) instead of `distinct` — real objects
# always get hooks lifted; identical layout, zero runtime cost.
#
# No matching upstream issue as of 2026-06-12 (#19250 is the same assert from
# an unrelated closure-in-seq trigger). Upstream issue draft:
# mx_rata_test repo, junk/nim_upstream_issue_draft.md.
import test_vow_arc_distinct_mod

put(Val())
echo "ok"
