## Tier 1 (pure) M2 anchor-ID suite -- dual-target: both `nim c -r` and
## `nim js -r` must pass.
##
## Proves `src/core/anchors.nim`'s stable heading-ID rules (M2 deliverable
## 3): slugs are stable across punctuation differences, duplicate
## headings anywhere in a document get deduped numeric suffixes, and
## dedup is flat across heading levels/nesting -- an anchor is a URL
## fragment, not scoped per section, so two same-text headings at
## different levels must still dedupe against each other.

import std/unittest
import ../../src/core/anchors

suite "docs anchor IDs -- stable slug + dedupe rules (Tier 1, dual-target)":
  test "slugifyHeadingText lowercases and collapses punctuation/whitespace to single hyphens":
    check slugifyHeadingText("Getting Started") == "getting-started"
    check slugifyHeadingText("Getting Started!") == "getting-started"
    check slugifyHeadingText("Getting, Started") == "getting-started"
    check slugifyHeadingText("  Getting   Started  ") == "getting-started"

  test "slugifyHeadingText trims leading/trailing punctuation rather than leaving stray hyphens":
    check slugifyHeadingText("--Hello--") == "hello"
    check slugifyHeadingText("!!!") == ""

  test "slugifyHeadingText is stable regardless of punctuation style used for the same words":
    check slugifyHeadingText("Signals & Effects") == slugifyHeadingText("Signals&Effects")
    check slugifyHeadingText("Signals & Effects!") == slugifyHeadingText("Signals & Effects")
    check slugifyHeadingText("Signals & Effects") == "signals-effects"

  test "AnchorIdRegistry gives the first occurrence of a slug the bare slug":
    var reg = newAnchorIdRegistry()
    check reg.nextId("Overview") == "overview"

  test "AnchorIdRegistry dedupes repeated headings with numeric suffixes in document order":
    var reg = newAnchorIdRegistry()
    check reg.nextId("Example") == "example"
    check reg.nextId("Example") == "example-2"
    check reg.nextId("Example") == "example-3"

  test "AnchorIdRegistry dedupes punctuation-equivalent duplicate headings against each other":
    var reg = newAnchorIdRegistry()
    check reg.nextId("Getting Started") == "getting-started"
    check reg.nextId("Getting Started!") == "getting-started-2"

  test "AnchorIdRegistry dedupes flatly across heading levels/nested sections":
    var reg = newAnchorIdRegistry()
    check reg.nextId("Overview") == "overview" # e.g. an H2
    check reg.nextId("Details") == "details" # an H3 nested under it
    check reg.nextId("Overview") == "overview-2" # a later H2 in a different section, same text

  test "AnchorIdRegistry falls back to a non-empty base for a heading with no alphanumeric characters":
    var reg = newAnchorIdRegistry()
    check reg.nextId("---") == "section"
    check reg.nextId("!!!") == "section-2"

  test "assignHeadingIds is a convenience batch form equivalent to sequential nextId calls":
    let ids = assignHeadingIds(@["Intro", "Details", "Intro"])
    check ids == @["intro", "details", "intro-2"]
