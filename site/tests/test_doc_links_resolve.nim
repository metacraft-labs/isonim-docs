## isonim-docs/site -- Verification test 4 (C-target only).
##
## Proves this site's own `content/` graph has NO dangling internal
## references: every internal doc link, every `#fragment` anchor, and every
## `[[sym:...]]` code-symbol cross-reference resolves. It runs the framework's
## OWN reference checker (`references.checkContentGraph` /
## `validateContentGraph`, which raises `BrokenReferenceError` on any broken
## reference) over the real, auto-discovered content graph -- the same
## `contentDir` + auto-discovered manifest the SSG builds -- and asserts it
## collects zero issues and does not raise. Real assertions, no skips.

import std/[unittest, os]
import core/routes
import core/content
import core/references

suite "isonim-docs self-docs -- internal references all resolve (Tier 3, C-target)":
  test "checkContentGraph over the whole content/ dir finds zero broken references":
    let repoRoot = currentSourcePath().parentDir().parentDir()
    let contentDir = repoRoot / "content"
    let manifest = buildManifestFromContent(contentDir)

    ## Sanity: there is a real, non-empty content graph to validate (a wiped
    ## content/ dir must fail this test, not pass it vacuously).
    let entries = loadContentEntries(contentDir)
    check entries.len > 0
    check manifest.entries.len >= entries.len

    ## checkContentGraph collects EVERY issue kind -- unknown routes, unknown
    ## anchors, duplicate routes, and unknown `[[sym:...]]` symbols -- across
    ## the whole graph together. The self-docs must have none.
    let issues = checkContentGraph(contentDir, manifest)
    for issue in issues:
      checkpoint formatReferenceIssue(issue)
    check issues.len == 0

  test "validateContentGraph (the enforcing CI form) does not raise over the clean content graph":
    let repoRoot = currentSourcePath().parentDir().parentDir()
    let contentDir = repoRoot / "content"
    let manifest = buildManifestFromContent(contentDir)

    ## `validateContentGraph` is the form `../check_links.nim` uses to fail a
    ## build: it raises `BrokenReferenceError` the instant any reference is
    ## broken. Over clean self-docs it must complete silently.
    var raised = false
    try:
      validateContentGraph(contentDir, manifest)
    except BrokenReferenceError:
      raised = true
    check not raised
