## isonim-docs — CI-facing broken-reference build gate (M3 deliverable 2).
##
## The concrete "fail the build" enforcement `references.validateContentGraph`
## exists for: run against a real content dir and its auto-discovered
## manifest (`routes.buildManifestFromContent`, M1 corrective deliverable
## 5 -- the framework's own checked-in `tests/fixtures/mini-site/` by
## default), wired into `just docs-smoke`/`just ci-docs` so a broken
## internal link, missing anchor fragment, or duplicate route fails a
## clean-checkout build with every issue's own actionable "file:line: ..."
## message, rather than shipping a dead link that only surfaces at
## runtime.

when defined(js):
  {.error: "check_links.nim is a C-target-only entry point".}

import ./core/routes
import ./core/references

when isMainModule:
  const contentDir = "tests/fixtures/mini-site"
  try:
    validateContentGraph(contentDir, buildManifestFromContent(contentDir))
    echo "docs references: OK"
  except BrokenReferenceError as e:
    stderr.writeLine(e.msg)
    quit(1)
