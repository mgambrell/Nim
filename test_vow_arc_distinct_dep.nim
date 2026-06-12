# KNOWN-FAILING (2026-06-12): cross-module `distinct` of a managed VALUE
# variant loses its lifted ARC hooks. NOT wired into test_vow.vow — this file
# documents an OPEN compiler bug; it becomes a real regression test the day
# the bug is fixed.
#
# Run:
#   bin/nim c -r --mm:arc test_vow_arc_distinct_dep.nim
#
# Current behavior:
#   - pre-b22b532f4 binary: compiler CRASH —
#       `injectdestructors.nim(499) not containsManagedMemory(nTyp)` assert
#   - rebuilt compiler (source >= b22b532f4): proper error at
#       test_vow_arc_distinct_mod.nim rbHashSet —
#       "passCopyToSink: type 'RbHashKey' contains managed memory but has
#        no attached =destroy"
#   - FIXED compiler: prints "ok" and exits 0.
#
# Required ingredients (remove any one and it compiles):
#   1. RbValue is a VALUE object variant with a managed (ref) arm.
#   2. RbHashKey = distinct RbValue, used as a Table key.
#   3. The type recurses THROUGH the distinct:
#        RbValue -> RbHash -> Table[distinct RbValue, RbValue].
#   4. The defining module is compiled as a DEPENDENCY (this import).
#      `nim c test_vow_arc_distinct_mod.nim` standalone is CLEAN — that is
#      the trap: the module's own tests pass, then the first importer dies.
#
# Mechanism (diagnosed, not fixed): attached ops live in the ModuleGraph
# keyed by PType itemId; sem only borrows base-type ops onto a distinct via
# produceSymDistinctType when createTypeBoundOps reaches it, and for this
# recursive-instantiation shape the distinct's PType instance arrives at
# injectdestructors' passCopyToSink with no ops attached. Workaround used in
# rbtranstest's rbvalue.vow: a plain wrapper `object` (field v: RbValue)
# instead of `distinct` — real objects always get hooks lifted, identical
# layout, zero runtime cost.
import test_vow_arc_distinct_mod

let h = RbHash()
rbHashSet(h, rbStr("k"), rbStr("v"))
echo "ok"
