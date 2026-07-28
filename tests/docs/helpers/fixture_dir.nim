## Real filesystem fixture-directory helper for the docs test harness
## (C-target only -- there's no real filesystem on the JS target).
##
## Per the M0 harness rule, fixtures are *real* files in a *real* temp
## directory, never an in-memory fake filesystem. Every caller of
## `withFixtureDir` gets a fresh, isolated directory that is removed
## again once the block returns, even if it raises.

when defined(js):
  {.error: "fixture_dir.nim is a C-target-only test helper".}

import std/[os, times, monotimes]

proc newFixtureDir*(prefix: string = "isonim_docs_fixture_"): string =
  ## Creates a fresh real temp directory and returns its path.
  result = getTempDir() / (prefix & $getCurrentProcessId() & "_" &
                            $epochTime().int64 & "_" & $getMonoTime().ticks)
  createDir(result)

proc removeFixtureDir*(dir: string) =
  removeDir(dir)

proc writeFixtureFile*(dir, relPath, content: string) =
  ## Writes `content` to a real file at `dir/relPath`, creating any
  ## intermediate directories a nested fixture path needs.
  let full = dir / relPath
  createDir(full.parentDir)
  writeFile(full, content)

template withFixtureDir*(body: untyped) =
  ## Injects `fixtureDir` (the real temp directory path) into `body` and
  ## removes it again afterwards, regardless of test outcome. Mirrors
  ## the injection style of `isonim/testing/test_utils.withFakeTime`.
  let fixtureDir {.inject.} = newFixtureDir()
  try:
    body
  finally:
    removeFixtureDir(fixtureDir)
