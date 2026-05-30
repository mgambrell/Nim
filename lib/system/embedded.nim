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
proc getFrame*(): PFrame {.compilerRtl, inl.} = nil
when not gotoBasedExceptions:
  var excHandler {.threadvar.}: PSafePoint
    ## Stack of active setjmp safepoints — the root of all try blocks on this
    ## thread. MBG: re-enabled so setjmp-exception builds (mv, gdevelop) can
    ## actually catch. goto builds still treat raise as fatal (see below).

  proc pushSafePoint(s: PSafePoint) {.compilerRtl, inl.} =
    s.prev = excHandler
    excHandler = s

  proc popSafePoint {.compilerRtl, inl.} =
    excHandler = excHandler.prev

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

# --- Unhandled-exception reporting -----------------------------------------
# MBG SPECIAL MOD: exception handling is treated as a bug: a raise always terminates the program. 
# No setjmp/longjmp unwinding, no goto-based, error flag, no catch.
# That's what we're rolling with for now, though I may need to make it configurable later
#
# Two platform hooks (both registered from host at startup):
#   mxrSetUnhandledExceptionLogger : receives a single fully-formatted cstring; expected to route to the engine's log stream.
#   mxrSetUnhandledExceptionAbortHook : fires after the log call, in case you decided not to terminate from there.

type
  MxrUnhandledExcLogger* = proc (msg: cstring) {.cdecl.}
  MxrUnhandledExcAbortHook* = proc () {.cdecl.}

var mxrUnhandledExcLogger: MxrUnhandledExcLogger
var mxrUnhandledExcAbortHook: MxrUnhandledExcAbortHook

proc mxrSetUnhandledExceptionLogger*(p: MxrUnhandledExcLogger) {.exportc, cdecl.} =
  mxrUnhandledExcLogger = p

proc mxrSetUnhandledExceptionAbortHook*(p: MxrUnhandledExcAbortHook) {.exportc, cdecl.} =
  mxrUnhandledExcAbortHook = p

proc c_snprintf(buf: cstring, size: csize_t, fmt: cstring) {.
    importc: "snprintf", header: "<stdio.h>", varargs, discardable.}
proc c_puts(s: cstring): cint {.importc: "puts", header: "<stdio.h>", discardable.}
proc c_fflush(stream: pointer): cint {.importc: "fflush", header: "<stdio.h>", discardable.}

proc fatalReport(e: ref Exception, procname, filename: cstring, line: int) {.nodestroy.} =
  # Assemble the whole report into
  var buf: array[2048, char]
  var nameStr: cstring = "(unknown)".cstring
  var msgStr: cstring = "".cstring
  if e != nil:
    if not e.name.isNil:
      nameStr = e.name
    if e.msg.len > 0:
      msgStr = e.msg.cstring
  let procStr: cstring = (if procname.isNil: "(?)".cstring else: procname)
  let fileStr: cstring = (if filename.isNil: "(?)".cstring else: filename)
  c_snprintf(cast[cstring](addr buf[0]), csize_t(sizeof(buf)),
             "FATAL: unhandled exception\n  type: %s\n  msg:  %s\n  at:   %s (%s:%d)".cstring,
             nameStr, msgStr, procStr, fileStr, line.cint)
  if mxrUnhandledExcLogger != nil:
    mxrUnhandledExcLogger(cast[cstring](addr buf[0]))
  else:
    discard c_puts(cast[cstring](addr buf[0]))
  discard c_fflush(nil)

proc fatalAbort() {.noreturn, nodestroy.} =
  # Run the platform's pre-abort hook (callstack/__debugbreak/minidump/etc.)
  # then terminate. The hook is expected to RETURN — abort happens here.
  if mxrUnhandledExcAbortHook != nil:
    mxrUnhandledExcAbortHook()
  quitOrDebug()

# MBG: setjmp-exception builds get real try/except unwinding (longjmp to the
# nearest safepoint). Only when there is NO active handler does a raise fall
# back to the original "exceptions are a bug" fatal report + abort. goto-based
# builds keep the old behavior (raise is fatal via the error-flag path).
proc raiseExceptionAux(e: sink(ref Exception), procname, filename: cstring, line: int) {.nodestroy.} =
  when not gotoBasedExceptions:
    if excHandler != nil:
      if e != currException:
        pushCurrentException(e)
      c_longjmp(excHandler.context, 1)
      return
  fatalReport(e, procname, filename, line)
  fatalAbort()

proc raiseExceptionEx(e: sink(ref Exception), ename, procname, filename: cstring, line: int) {.compilerRtl, nodestroy.} =
  if e.name.isNil: e.name = ename
  raiseExceptionAux(e, procname, filename, line)

proc raiseException(e: sink(ref Exception), ename: cstring) {.compilerRtl.} =
  raiseExceptionEx(e, ename, nil, nil, 0)

proc reraiseException() {.compilerRtl.} =
  if currException == nil:
    fatalReport(nil, "(reraise)".cstring, nil, 0)
    fatalAbort()
  else:
    raiseExceptionAux(currException, nil, nil, 0)

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
