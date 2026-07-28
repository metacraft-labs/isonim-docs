## Chronicles log-capture helper (C-target only) for the M0 test
## harness.
##
## chronicles has no first-class in-process capture-sink precedent
## anywhere else in the IsoNim family -- the design-review CLI
## (../isonim/src/isonim/editor/design_review/log_setup.nim) just wires
## a compile-time sink and never captures its own output in a test. The
## simplest approach that doesn't need a second, test-only compile-time
## sink configuration: redirect the real OS-level file descriptor
## chronicles' configured sink writes to (`textlines[stderr]`, pinned in
## ../config.nims) around the code under test, then read back what was
## written. chronicles flushes its sink after every record (see
## chronicles/log_output.nim's `flushRecord`), so no extra flush dance
## on chronicles' side is needed beyond flushing our own `stderr`
## handle before/after the redirect.

when defined(js):
  {.error: "log_capture.nim is a C-target-only test helper".}

import std/[os, posix]

proc captureStderr*(action: proc()): string =
  ## Runs `action` with the process's real stderr fd redirected to a
  ## fresh temp file, then returns everything written to it, restoring
  ## the original stderr fd afterwards (even if `action` raises).
  let tmpPath = getTempDir() / ("isonim_docs_stderr_capture_" & $getCurrentProcessId() & ".log")
  let tmpFile = open(tmpPath, fmWrite)
  stderr.flushFile()
  let savedFd = dup(cint(2))
  discard dup2(cint(tmpFile.getFileHandle()), cint(2))
  try:
    action()
    stderr.flushFile()
  finally:
    discard dup2(savedFd, cint(2))
    discard close(savedFd)
    tmpFile.close()
  result = readFile(tmpPath)
  removeFile(tmpPath)
