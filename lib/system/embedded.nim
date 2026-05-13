#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Standalone implementation with working exception handling.

proc chckIndx(i, a, b: int): int {.inline, compilerproc.}
proc chckRange(i, a, b: int): int {.inline, compilerproc.}
proc chckRangeF(x, a, b: float): float {.inline, compilerproc.}
proc chckNil(p: pointer) {.inline, compilerproc.}

proc nimFrame(s: PFrame) {.compilerRtl, inl, exportc: "nimFrame".} = discard
proc popFrame {.compilerRtl, inl.} = discard

proc setFrame(s: PFrame) {.compilerRtl, inl.} = discard
when not gotoBasedExceptions:
  proc pushSafePoint(s: PSafePoint) {.compilerRtl, inl.} = discard
  proc popSafePoint {.compilerRtl, inl.} = discard

var currException {.threadvar.}: ref Exception

when gotoBasedExceptions:
  var nimInErrorMode {.threadvar.}: bool

proc pushCurrentException(e: sink(ref Exception)) {.compilerRtl, inl.} =
  e.up = currException
  currException = e

proc popCurrentException {.compilerRtl, inl.} =
  currException = currException.up

proc closureIterSetExc(e: ref Exception) {.compilerRtl, inl.} =
  currException = e

proc nimBorrowCurrentException(): ref Exception {.compilerRtl, inl, benign, nodestroy.} =
  result = currException

proc getCurrentException*(): ref Exception {.compilerRtl, inl, benign.} =
  result = currException

proc getCurrentExceptionMsg*(): string {.inline, benign.} =
  return if currException == nil: "" else: currException.msg

proc setCurrentException*(exc: ref Exception) {.inline, benign.} =
  currException = exc

# some platforms have native support for stack traces:
const
  nativeStackTraceSupported = false
  hasSomeStackTrace = false

proc quitOrDebug() {.noreturn, importc: "abort", header: "<stdlib.h>", nodecl.}

proc raiseExceptionAux(e: sink(ref Exception)) {.nodestroy.} =
  pushCurrentException(e)
  when gotoBasedExceptions:
    inc nimInErrorMode

proc raiseExceptionEx(e: sink(ref Exception), ename, procname, filename: cstring,
                      line: int) {.compilerRtl, nodestroy.} =
  if e.name.isNil: e.name = ename
  raiseExceptionAux(e)

proc raiseException(e: sink(ref Exception), ename: cstring) {.compilerRtl.} =
  raiseExceptionEx(e, ename, nil, nil, 0)

proc reraiseException() {.compilerRtl.} =
  if currException == nil:
    sysFatal(ReraiseDefect, "no exception to reraise")
  else:
    when gotoBasedExceptions:
      inc nimInErrorMode
    else:
      raiseExceptionAux(currException)

proc raiseDefect() {.compilerRtl.} =
  rawQuit(1)

proc writeStackTrace() = discard

proc unsetControlCHook() = discard
proc setControlCHook(hook: proc () {.noconv.}) = discard

when gotoBasedExceptions:
  proc nimErrorFlag(): ptr bool {.compilerRtl, inl.} =
    result = addr(nimInErrorMode)

  proc nimTestErrorFlag() {.compilerRtl.} =
    if nimInErrorMode and currException != nil:
      currException = nil
      rawQuit(1)
