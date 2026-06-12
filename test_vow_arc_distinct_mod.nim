# KNOWN-FAILING repro module — cross-module distinct-of-managed-value ARC bug.
# See test_vow_arc_distinct_dep.nim (the importer) for the full story and the
# run line. This module compiles CLEAN standalone; the bug only fires when it
# is pulled in as a dependency.
import std/tables
import std/hashes

type
  RbKind* = enum rkNil, rkStr, rkHash
  RbString* = ref object
    buf*: string
  RbHashKey* = distinct RbValue
  RbHash* = ref object
    pairs*: Table[RbHashKey, RbValue]
  RbValue* = object
    case kind*: RbKind
    of rkNil: discard
    of rkStr: sv*: RbString
    # The recursion is a REQUIRED ingredient: RbValue -> RbHash ->
    # Table[distinct RbValue, RbValue]. Dropping this arm makes the
    # whole thing compile.
    of rkHash: hv*: RbHash

proc `==`*(a, b: RbHashKey): bool =
  RbValue(a).kind == RbValue(b).kind

proc hash*(k: RbHashKey): Hash =
  hash(ord(RbValue(k).kind))

proc rbStr*(s: string): RbValue = RbValue(kind: rkStr, sv: RbString(buf: s))

proc rbHashSet*(h: RbHash, k: RbValue, v: RbValue) =
  # The lvalue-to-sink conversion `RbHashKey(k)` is where injectdestructors
  # notices the distinct type arrived without attached hooks.
  h.pairs[RbHashKey(k)] = v
