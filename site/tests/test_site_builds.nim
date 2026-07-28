## isonim-docs/site -- Verification test 1 (C-target only).
##
## Proves this site's own `content/` dir, addressed purely via the
## framework's auto-discovery (no explicit manifest passed anywhere --
## `ssr.nim`'s own `renderRoute` wrapper never supplies one either),
## renders every page with its own real title and this site's own
## branding, AND that the real on-disk `buildSite()` (the exact path
## `just build`/`src/build.nim` takes) emits a `public/` with a
## non-dangling themed stylesheet, a search index, and a sitemap.

import std/[unittest, os, strutils]
import core/routes
import core/content
import build_site          ## the framework's real on-disk SSG entry
import ../src/ssr
import ../src/docs_config  ## this site's own DocsConfig (isonimDocsDocsConfig)

const ExpectedPageCount = 17
  ## M1's 5 core pages (index + getting-started + routing + theming +
  ## markdown) plus M2's 12 feature-reference pages (navigation-and-search,
  ## seo, api-reference, library-reference, components, tutorials, plugins,
  ## dev-server, cli, deployment, security, features).

suite "isonim-docs self-docs -- auto-discovered routes all render (Tier 3, C-target)":
  test "every real content/ page auto-discovers to a route that renders 200 with its own title":
    let repoRoot = currentSourcePath().parentDir().parentDir()
    let contentDir = repoRoot / "content"
    let manifest = buildManifestFromContent(contentDir)
    let entries = loadContentEntries(contentDir)

    check entries.len == ExpectedPageCount
    check manifest.entries.len == entries.len

    for entry in manifest.entries:
      check entry.status == rsOk
      check entry.meta.title.len > 0
      let (status, html) = renderRoute(entry.canonicalPath, contentDir)
      check status == 200
      check html.contains(entry.meta.title)
      check html.contains("isonim-docs") # this site's own DocsConfig branding

proc extractStylesheetHref(html: string): string =
  ## Pull the `href` out of the document's `<link rel="stylesheet" ...>`
  ## exactly as the browser would resolve it.
  const relMarker = "rel=\"stylesheet\""
  let relPos = html.find(relMarker)
  doAssert relPos >= 0, "emitted index.html has no <link rel=\"stylesheet\">"
  const hrefKey = "href=\""
  let hrefPos = html.find(hrefKey, relPos)
  doAssert hrefPos >= 0, "stylesheet <link> has no href"
  let start = hrefPos + hrefKey.len
  let stop = html.find('"', start)
  doAssert stop > start, "stylesheet href attribute is unterminated"
  html[start ..< stop]

suite "isonim-docs self-docs -- real on-disk buildSite() emits a non-dangling public/ (Tier 3, C-target)":
  test "buildSite() into a temp dir: pages + non-dangling hashed stylesheet + sitemap + search index on disk":
    let repoRoot = currentSourcePath().parentDir().parentDir()
    let contentDir = repoRoot / "content"
    let assetsDir = repoRoot / "assets"
    let outDir = getTempDir() / "isonim_docs_site_ondisk_build"

    ## Drive the SAME entry `src/build.nim` uses -- this site's own
    ## `content/`, own `assets/`, own `DocsConfig` -- into a temp `public/`.
    let pageCount = buildSite(outDir = outDir, contentDir = contentDir,
                              cfg = isonimDocsDocsConfig(), assetsDir = assetsDir)

    ## 1. Build exited success and rendered every real content page.
    check pageCount == ExpectedPageCount

    ## 2. public/index.html exists on disk, non-empty, with this site's branding.
    let indexPath = outDir / "index.html"
    check fileExists(indexPath)
    let indexHtml = readFile(indexPath)
    check indexHtml.len > 0
    check indexHtml.contains("isonim-docs")

    ## 3. The stylesheet the emitted page references exists on disk and is
    ## non-empty -- i.e. `stylesheetHref` is NOT dangling. The declared
    ## href is `/assets/style.css`; the build's hash+purge pipeline
    ## rewrites it to a content-hashed name.
    let cssHref = extractStylesheetHref(indexHtml)
    check cssHref.startsWith("/assets/style.")
    check cssHref.endsWith(".css")
    check cssHref != "/assets/style.css" # proves the hash/purge pipeline ran
    let cssPath = outDir / cssHref[1 .. ^1]
    check fileExists(cssPath)
    check getFileSize(cssPath) > 0

    ## 4. A non-root real content page also landed on disk (guard against a
    ## build that emits only "/").
    let guidePath = outDir / "getting-started" / "index.html"
    check fileExists(guidePath)
    check getFileSize(guidePath) > 0

    ## 5. SEO + search artifacts: sitemap.xml and a content-hashed
    ## search-index.<hash>.json are present and non-empty.
    let sitemapPath = outDir / "sitemap.xml"
    check fileExists(sitemapPath)
    check getFileSize(sitemapPath) > 0
    var searchIndexFound = false
    for kind, path in walkDir(outDir):
      if kind == pcFile:
        let name = path.extractFilename
        if name.startsWith("search-index.") and name.endsWith(".json"):
          searchIndexFound = getFileSize(path) > 0
    check searchIndexFound

    removeDir(outDir)
