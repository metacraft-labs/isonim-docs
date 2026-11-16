## Tier 3 (C-target SSG + DevServer) suite for built-in opt-in agent discovery
## (`DocsConfig.emitLlmsTxt`): `/llms.txt`, `/llms-full.txt`, `_headers`, and
## `robots.txt` pointer.

import std/[unittest, os, strutils]
import ../../src/core/config
import ../../src/build_site
import ../../src/dev_server

suite "DocsConfig.emitLlmsTxt (SSG + DevServer, opt-in)":
  test "default docsConfig() leaves llms.txt, llms-full.txt and _headers un-emitted":
    let outDir = getTempDir() / ("isonim-docs-llms-off-" & $getCurrentProcessId())
    removeDir(outDir)
    defer: removeDir(outDir)

    let count = buildSite(outDir = outDir, contentDir = "tests/fixtures/mini-site",
                          cfg = docsConfig())
    check count > 0
    check not fileExists(outDir / "llms.txt")
    check not fileExists(outDir / "llms-full.txt")
    check not fileExists(outDir / "_headers")

  test "emitLlmsTxt: true emits llms.txt, llms-full.txt, _headers and robots.txt pointer":
    let outDir = getTempDir() / ("isonim-docs-llms-on-" & $getCurrentProcessId())
    removeDir(outDir)
    defer: removeDir(outDir)

    var cfg = docsConfig()
    cfg.siteTitle = "Example Docs"
    cfg.siteDescription = "Structured docs for humans and AI agents."
    cfg.baseUrl = "https://docs.example.test"
    cfg.emitLlmsTxt = true

    let count = buildSite(outDir = outDir, contentDir = "tests/fixtures/mini-site", cfg = cfg)
    check count > 0
    check fileExists(outDir / "llms.txt")
    check fileExists(outDir / "llms-full.txt")
    check fileExists(outDir / "_headers")

    let llms = readFile(outDir / "llms.txt")
    check llms.startsWith("# Example Docs\n\n> Structured docs for humans and AI agents.")
    check "https://docs.example.test/index.md" in llms
    check "https://docs.example.test/llms-full.txt" in llms
    check fileExists(outDir / "index.md")
    check fileExists(outDir / "index.html.md")
    check fileExists(outDir / "getting-started.md")
    check fileExists(outDir / "getting-started/index.html.md")
    check readFile(outDir / "index.md").startsWith("# ")
    let homeHtml = readFile(outDir / "index.html")
    check "<link rel=\"alternate\" type=\"text/markdown\" href=\"/index.md\">" in homeHtml
    check "<link rel=\"describedby\" type=\"text/markdown\" href=\"/llms.txt\">" in homeHtml

    let llmsFull = readFile(outDir / "llms-full.txt")
    check "# Example Docs" in llmsFull
    check "URL: https://docs.example.test/" in llmsFull

    let headers = readFile(outDir / "_headers")
    check "Link: </llms.txt>; rel=\"describedby\"; type=\"text/markdown\", </llms.txt>; rel=\"llms-txt\", </llms-full.txt>; rel=\"llms-full-txt\"" in headers
    check "Content-Type: text/plain; charset=utf-8" in headers
    check "Content-Type: text/markdown; charset=utf-8" in headers

    let robots = readFile(outDir / "robots.txt")
    check "https://docs.example.test/llms.txt" in robots

  test "consumer-supplied llms.txt in publicDir is preserved verbatim":
    let work = getTempDir() / ("isonim-docs-llms-custom-" & $getCurrentProcessId())
    let pubSrc = work / "pub"
    let outDir = work / "out"
    removeDir(work)
    createDir(pubSrc)
    defer: removeDir(work)

    writeFile(pubSrc / "llms.txt", "# Custom Agent Index\n")
    var cfg = docsConfig()
    cfg.emitLlmsTxt = true
    discard buildSite(outDir = outDir, contentDir = "tests/fixtures/mini-site",
                      cfg = cfg, publicDir = pubSrc)
    check readFile(outDir / "llms.txt") == "# Custom Agent Index\n"
    check fileExists(outDir / "llms-full.txt")

  test "DevServer serves /llms.txt and /llms-full.txt as plain text when emitLlmsTxt is true":
    var cfg = docsConfig()
    cfg.siteTitle = "Live Dev Docs"
    cfg.baseUrl = "http://127.0.0.1:8000"
    cfg.emitLlmsTxt = true

    let srv = newDevServer(contentDir = "tests/fixtures/mini-site", cfg = cfg)
    let r1 = srv.handleRoute("/llms.txt")
    check r1.status == 200
    check r1.contentType == "text/plain; charset=utf-8"
    check "# Live Dev Docs" in r1.body

    let r2 = srv.handleRoute("/llms-full.txt")
    check r2.status == 200
    check r2.contentType == "text/plain; charset=utf-8"
    check "# Live Dev Docs" in r2.body

    let r3 = srv.handleRoute("/index.md")
    check r3.status == 200
    check r3.contentType == "text/markdown; charset=utf-8"
    check r3.body.startsWith("# ")
