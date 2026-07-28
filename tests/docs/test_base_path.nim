## Tests for base-path (project-subpath) hosting: the `core/base_path`
## helpers and their end-to-end effect through `buildSite`. The default
## (empty `basePath`) must leave every emitted URL root-relative and
## byte-identical; a set `basePath` must prefix every internal root-relative
## URL (page href/src/search-index attr, stylesheet `url(...)`, search-index
## routePaths) while leaving absolute/protocol-relative/fragment URLs alone.

import std/[unittest, os, strutils]
import ../../src/core/base_path
import ../../src/core/config
import ../../src/build_site

suite "base_path helpers":
  test "normalizeBasePath canonicalizes":
    check normalizeBasePath("") == ""
    check normalizeBasePath("   ") == ""
    check normalizeBasePath("/") == ""
    check normalizeBasePath("isonim-docs") == "/isonim-docs"
    check normalizeBasePath("/isonim-docs") == "/isonim-docs"
    check normalizeBasePath("/isonim-docs/") == "/isonim-docs"

  test "empty base is a strict no-op":
    let s = "<a href=\"/x\"><img src=\"/y\"> url(/z) \"routePath\":\"/w\" href=\"//cdn\""
    check applyBasePathHtml(s, "") == s
    check applyBasePathCss(s, "") == s
    check applyBasePathSearchIndex(s, "") == s

  test "html prefixes only root-relative href/src/data-search-index-url":
    let b = "/base"
    check applyBasePathHtml("<a href=\"/getting-started\">", b) ==
      "<a href=\"/base/getting-started\">"
    check applyBasePathHtml("<img src=\"/assets/x.png\">", b) ==
      "<img src=\"/base/assets/x.png\">"
    check applyBasePathHtml("<div data-search-index-url=\"/search-index.abc.json\">", b) ==
      "<div data-search-index-url=\"/base/search-index.abc.json\">"
    check applyBasePathHtml("<a href=\"/\">home</a>", b) == "<a href=\"/base/\">home</a>"

  test "html leaves absolute / protocol-relative / fragment / relative alone":
    let b = "/base"
    check applyBasePathHtml("<a href=\"https://x.com/y\">", b) == "<a href=\"https://x.com/y\">"
    check applyBasePathHtml("<a href=\"//cdn/y\">", b) == "<a href=\"//cdn/y\">"
    check applyBasePathHtml("<a href=\"#anchor\">", b) == "<a href=\"#anchor\">"
    check applyBasePathHtml("<a href=\"relative/y\">", b) == "<a href=\"relative/y\">"
    # A canonical <link> uses an absolute URL and must not be double-prefixed.
    check applyBasePathHtml("<link rel=\"canonical\" href=\"https://h/isonim-docs/p\">", b) ==
      "<link rel=\"canonical\" href=\"https://h/isonim-docs/p\">"

  test "css prefixes root-relative url() (bare + quoted), not data:/absolute":
    let b = "/base"
    check applyBasePathCss("src: url(/assets/f.woff2)", b) == "src: url(/base/assets/f.woff2)"
    check applyBasePathCss("src: url(\"/assets/f.woff2\")", b) == "src: url(\"/base/assets/f.woff2\")"
    check applyBasePathCss("src: url('/assets/f.woff2')", b) == "src: url('/base/assets/f.woff2')"
    check applyBasePathCss("url(https://x/f)", b) == "url(https://x/f)"
    check applyBasePathCss("url(data:font/woff2;base64,AAAA)", b) == "url(data:font/woff2;base64,AAAA)"

  test "search index prefixes routePath values":
    check applyBasePathSearchIndex("{\"routePath\":\"/guide\",\"title\":\"G\"}", "/base") ==
      "{\"routePath\":\"/base/guide\",\"title\":\"G\"}"

suite "base_path through buildSite":
  # The framework's own mini-site fixture + assets (relative to the repo root,
  # which is the CWD when tests run via `nim c -r tests/docs/...`).
  let tmp = getTempDir() / "isonim_docs_basepath_test"

  test "empty basePath keeps asset/nav links root-relative":
    let outDir = tmp / "root"
    removeDir(outDir)
    var cfg = docsConfig()
    check cfg.basePath == ""            # framework default
    discard buildSite(outDir = outDir, cfg = cfg)
    let idx = readFile(outDir / "index.html")
    check "href=\"/assets/" in idx      # stylesheet link is root-relative
    check "/root/" notin idx

  test "set basePath prefixes pages, stylesheet, and search index":
    let outDir = tmp / "sub"
    removeDir(outDir)
    var cfg = docsConfig()
    cfg.basePath = "/isonim-docs"
    cfg.baseUrl = "https://metacraft-labs.github.io/isonim-docs"
    discard buildSite(outDir = outDir, cfg = cfg)
    let idx = readFile(outDir / "index.html")
    check "href=\"/isonim-docs/assets/" in idx   # stylesheet prefixed
    check "href=\"/assets/" notin idx            # NO unprefixed asset link survives
    # canonical stays absolute (carries the subpath via baseUrl), not double-prefixed
    check "https://metacraft-labs.github.io/isonim-docs" in idx
    check "/isonim-docs/isonim-docs" notin idx
    # the hashed search index file exists and its routePaths are prefixed
    var found = false
    for f in walkDirRec(outDir):
      if f.extractFilename.startsWith("search-index.") and f.endsWith(".json"):
        check "\"routePath\":\"/isonim-docs/" in readFile(f)
        found = true
    check found
