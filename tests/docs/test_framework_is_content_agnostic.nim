## Tier 1 (pure) M1 corrective deliverable 3 suite -- dual-target: both
## `nim c -r` and `nim js -r` must pass.
##
## Guards against re-coupling: proves the framework's own defaults --
## `core/config.docsConfig()` and `core/completeness.requiredCompletenessMatrix()`
## -- carry zero IsoNim-specific data (M1 corrective deliverable 3), and
## that the framework's own route-building path
## (`routes.buildManifestFromEntries`, fed by a tiny hand-built, non-IsoNim
## mini fixture graph -- no filesystem access, so this stays dual-target)
## renders zero IsoNim-specific routes/titles. M1 corrective deliverable 4
## moved the IsoNim-specific config/matrix data that used to be staged in
## the framework's own `docs_site.nim` out to the consumer package
## (`../isonim/docs/users/src/docs_config.nim`) entirely -- the framework
## itself now carries none of it, anywhere. The real, real-filesystem-driven
## render of the *actual* checked-in fixture tree in
## `tests/fixtures/mini-site/` is `renderRoute`/`createRouteApp`'s own
## existing Tier-3 suites' job, not this one's.

import std/[unittest, strutils]
import ../../src/core/config
import ../../src/core/completeness
import ../../src/core/content
import ../../src/core/routes

proc mentionsIsonim(s: string): bool =
  s.toLowerAscii().contains("isonim")

suite "framework defaults -- docsConfig/requiredCompletenessMatrix carry zero IsoNim data (Tier 1, dual-target)":
  test "the framework's default DocsConfig names no site":
    let cfg = docsConfig()
    check not mentionsIsonim(cfg.siteTitle)
    check not mentionsIsonim(cfg.siteDescription)

  test "the framework's default completeness matrix is empty":
    check requiredCompletenessMatrix().len == 0

suite "framework routing -- a non-IsoNim content graph builds a manifest with zero IsoNim routes/titles (Tier 1, dual-target)":
  test "buildManifestFromEntries over a hand-built mini fixture graph never mentions IsoNim":
    let entries = @[
      parseContentEntry("# Welcome\n\nThis is a tiny fixture site.", "index.md"),
      parseContentEntry("# About This Fixture\n\nJust two pages.", "about.md"),
    ]
    let manifest = buildManifestFromEntries(entries)
    check manifest.entries.len == 2
    for entry in manifest.entries:
      check not mentionsIsonim(entry.canonicalPath)
      check not mentionsIsonim(entry.meta.title)
