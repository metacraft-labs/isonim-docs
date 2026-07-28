## isonim-docs static site generator (SSG).
##
## Renders every route in `manifest` (by default, auto-discovered from
## `contentDir`) through the shared `renderRoute` (the exact same SSR path
## the server and the renderRoute tests use) to static HTML, using
## clean-URL `<route>/index.html` output. This is the production-build
## entry (M4 deliverable 5): one component codebase → SSG here, SSR via
## `ssr.nim`, SPA via `main_web.nim`.

when defined(js):
  {.error: "build_site.nim is a C-target (SSG) entry; not for the JS target".}

import std/[os, strutils, sets]
import chronicles
import ./ssr
import ./core/routes
import ./core/config
import ./core/plugin
import ./core/search_vm
import ./components/search_view
import ./core/asset_pipeline

const bundledDefaultStylesheet = staticRead("../assets/style.css")
  ## The framework's own content-agnostic, token-driven stylesheet,
  ## embedded at compile time so `buildSite` can provision it as a
  ## fallback whenever the site being built ships no (non-empty)
  ## `assets/style.css` of its own -- the last-resort guarantee that a
  ## declared `stylesheetHref` can never dangle (M1 corrective
  ## deliverable 1). Single source of truth: it IS `assets/style.css`,
  ## so the fallback can never drift from the framework's real stylesheet.

proc outputPathFor(outDir, routePath: string): string =
  ## Clean-URL mapping: "/" -> index.html, "/guide/dsl" -> guide/dsl/index.html.
  let trimmed = routePath.strip(chars = {'/'})
  if trimmed.len == 0: outDir / "index.html"
  else: outDir / trimmed / "index.html"

proc copyAssetsVerbatim(outDir, assetsDir: string; docsTokensCss = "") =
  ## Verbatim-copies `assetsDir` (the framework's or a consumer's own
  ## `assets/`, holding at minimum `style.css`) into `outDir/assets/`.
  ## If no non-empty `style.css` lands (the site ships no `assets/` dir,
  ## or one without a stylesheet), the framework's own bundled default is
  ## provisioned in its place -- so `stylesheetHref` is made structurally
  ## unable to dangle (M2/M1 corrective deliverable 1), not merely
  ## asserted after the fact. The trailing `doAssert` then only documents
  ## an invariant the provisioning already guarantees. This is the
  ## pre-hash copy; `hashAndPurgeAssets` below turns it into the real
  ## deliverable-3 pipeline (hashed filenames, manifest, purge).
  ##
  ## `docsTokensCss` (metacraft-theme M1 deliverable 3) is an OPTIONAL,
  ## consumer-supplied block of `:root{ --docs-*: ... }` token CSS emitted
  ## by `core/docs_tokens.emitTokensCss`. When non-empty it is PREPENDED to
  ## `style.css` before the hash/purge step, so the docs token layer rides
  ## the existing pipeline unchanged as part of the single, hashed
  ## stylesheet the pages already reference (no extra asset, no `@import`
  ## that hashing would break). When empty (the framework default) nothing
  ## is prepended and the output is byte-identical to before -- the
  ## emitter is strictly opt-in.
  if dirExists(assetsDir):
    copyDir(assetsDir, outDir / "assets")
  let cssPath = outDir / "assets" / "style.css"
  if not (fileExists(cssPath) and getFileSize(cssPath) > 0):
    ## No consumer-supplied stylesheet landed -- whether the site ships
    ## no `assets/` dir at all, or an `assets/` dir without a (non-empty)
    ## `style.css`. Provision the framework's own bundled default so the
    ## build proceeds with a real, on-disk stylesheet instead of aborting;
    ## this is what makes a declared `stylesheetHref` structurally unable
    ## to dangle (M1 corrective deliverable 1).
    createDir(outDir / "assets")
    writeFile(cssPath, bundledDefaultStylesheet)
    info "ssg_default_stylesheet_provisioned", path = cssPath,
      bytes = bundledDefaultStylesheet.len
  doAssert fileExists(cssPath) and getFileSize(cssPath) > 0,
    "build_site: " & cssPath & " must exist and be non-empty " &
    "(stylesheetHref must never dangle) -- checked " & assetsDir & "/style.css"
  if docsTokensCss.len > 0:
    writeFile(cssPath, docsTokensCss & "\n" & readFile(cssPath))
    info "ssg_docs_tokens_prepended", path = cssPath, bytes = docsTokensCss.len

proc hashAndPurgeAssets(outDir: string, usedClasses: HashSet[string]):
    seq[tuple[fromHref, toHref: string]] =
  ## M2 corrective deliverable 3: Tailwind-purges `style.css` against
  ## the classes actually used across every rendered page, then
  ## content-hashes every file under `outDir/assets` in place (removing
  ## the unhashed copy) and writes `asset-manifest.json`. Returns the
  ## `/assets/<name>` -> `/assets/<hashed name>` href rewrites the
  ## caller must apply to already-rendered HTML.
  var relPaths: seq[string] = @[]
  for relPath in walkDirRec(outDir / "assets", relative = true):
    relPaths.add relPath
  var manifestEntries: seq[tuple[original, hashed: string]] = @[]
  result = @[]
  for relPath in relPaths:
    let absPath = outDir / "assets" / relPath
    if not fileExists(absPath): continue
    var content = readFile(absPath)
    if relPath == "style.css":
      content = purgeCss(content, usedClasses)
    let hashedRel = hashedAssetName(relPath, content)
    let hashedAbs = outDir / "assets" / hashedRel
    createDir(hashedAbs.parentDir)
    writeFile(hashedAbs, content)
    removeFile(absPath)
    if relPath == "style.css":
      doAssert fileExists(hashedAbs) and getFileSize(hashedAbs) > 0,
        "build_site: " & hashedAbs & " (purged+hashed stylesheet) must " &
        "exist and be non-empty -- stylesheetHref must never dangle"
    manifestEntries.add ("assets/" & relPath, "assets/" & hashedRel)
    result.add ("/assets/" & relPath, "/assets/" & hashedRel)
  writeAssetManifest(outDir / "asset-manifest.json", manifestEntries)

proc xmlEscape(s: string): string =
  ## Minimal XML text/attribute escaper for the sitemap `<loc>` values.
  for c in s:
    case c
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&apos;"
    else: result.add c

proc collectSeoWarnings*(manifest: RouteManifest): seq[string] =
  ## M6 deliverable 1: a page lacking a description (or a title) is a real
  ## SEO gap, so it is surfaced as an observable build WARNING rather than
  ## silently shipped -- but never a hard failure (authored content
  ## shouldn't fail a build over a missing meta field). Pure over the
  ## manifest's typed metadata, so it is independently testable; `buildSite`
  ## both logs each warning and (when given a `warnings` collection)
  ## returns them for a caller/test to assert on.
  for entry in manifest.entries:
    if entry.pageKind == pkRedirect:
      continue ## redirect/alias entries have no page + no meta of their own
    if entry.meta.description.len == 0:
      result.add "page '" & entry.canonicalPath & "' is missing a description"
    if entry.meta.title.len == 0:
      result.add "page '" & entry.canonicalPath & "' is missing a title"

proc writeSitemapAndRobots(outDir: string; manifest: RouteManifest; cfg: DocsConfig) =
  ## M6 deliverable 1: emit `sitemap.xml` (every real, non-redirect route
  ## as an absolute URL derived from `cfg.baseUrl`) and a sensible default
  ## `robots.txt` (allow all + a `Sitemap:` line) into the output dir. A
  ## consumer-supplied `robots.txt` (copied verbatim from `publicDir`)
  ## wins: it is never overwritten.
  var urls = ""
  for entry in manifest.entries:
    if entry.pageKind == pkRedirect:
      continue
    urls.add "  <url><loc>" & xmlEscape(joinSiteUrl(cfg.baseUrl, entry.canonicalPath)) &
      "</loc></url>\n"
  let sitemap = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" &
    "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n" &
    urls & "</urlset>\n"
  writeFile(outDir / "sitemap.xml", sitemap)
  info "ssg_sitemap_written", path = outDir / "sitemap.xml", bytes = sitemap.len

  let robotsPath = outDir / "robots.txt"
  if not fileExists(robotsPath):
    var robots = "User-agent: *\nAllow: /\n"
    robots.add "Sitemap: " & joinSiteUrl(cfg.baseUrl, "/sitemap.xml") & "\n"
    writeFile(robotsPath, robots)
    info "ssg_robots_written", path = robotsPath, bytes = robots.len

proc buildSite*(outDir = "public"; contentDir = "tests/fixtures/mini-site";
                 manifest: RouteManifest = buildManifestFromContent(contentDir);
                 cfg: DocsConfig = docsConfig(); assetsDir = "assets";
                 publicDir = ""; warnings: ref seq[string] = nil;
                 host: PluginHost = PluginHost(); docsTokensCss = ""): int =
  ## Statically generates the whole site; returns the page count.
  ## `manifest`'s framework default (M1 corrective deliverable 2)
  ## auto-discovers the route table from `contentDir`, exactly like
  ## `renderRoute`'s own default -- passing an explicit `manifest` (e.g.
  ## the hand-authored `docsRouteManifest()`) still fully overrides it.
  ## `cfg` defaults to the framework's own content-agnostic `docsConfig()`
  ## (M1 corrective deliverable 3); a real site passes its own
  ## `DocsConfig` explicitly. `publicDir`, if present, is a consumer's
  ## own passthrough dir (favicons, robots.txt, ...) copied verbatim
  ## into `outDir` -- unlike `assetsDir`, never hashed or purged. M6
  ## deliverable 1: `warnings`, if given, receives the observable SEO
  ## build warnings (a page missing description/title) this build produced
  ## -- they are always logged via the structured `ssg_*` logger too,
  ## never silent, and never a hard failure.
  ## M11 deliverable 1: resolve the config through every `onConfig` hook
  ## ONCE, at the start of the build, so every downstream artifact
  ## (rendered pages, sitemap, robots) sees the same plugin-adjusted
  ## config. An empty host leaves `cfg` untouched.
  var cfg = cfg
  applyOnConfig(host, cfg)

  removeDir(outDir)
  createDir(outDir)
  copyAssetsVerbatim(outDir, assetsDir, docsTokensCss)
  if dirExists(publicDir):
    copyDir(publicDir, outDir)

  ## M6 deliverable 1: surface missing description/title as observable
  ## warnings (logged + optionally returned), before rendering anything.
  let seoWarnings = collectSeoWarnings(manifest)
  for w in seoWarnings:
    warn "ssg_seo_warning", detail = w
  if not warnings.isNil:
    warnings[] = seoWarnings

  ## Render every route once, up front, so the purge step below sees
  ## every class used anywhere on the site before any asset is hashed.
  var pages: seq[tuple[outPath, html: string]] = @[]
  var usedClasses = initHashSet[string]()
  for entry in manifest.entries:
    if entry.pageKind == pkRedirect:
      continue ## alias/redirect entries have no static page of their own
    let routePath = entry.canonicalPath
    let (status, html) = renderRoute(routePath, contentDir, manifest, cfg, host = host)
    pages.add (outputPathFor(outDir, routePath), html)
    usedClasses.incl extractUsedClasses(html)
    info "ssg_page_rendered", route = routePath, status = status, bytes = html.len

  var hrefRewrites = hashAndPurgeAssets(outDir, usedClasses)

  ## M5 deliverable 2 (deferred search index): emit the real, site-wide
  ## search index as a SEPARATE, content-hashed `search-index.<hash>.json`
  ## artifact at the site root (never inlined into any page's HTML), and
  ## register the placeholder->hashed rewrite so every page's search
  ## overlay `data-search-index-url` points at the cache-busted artifact --
  ## exactly the same content-hash + href-rewrite pipeline the stylesheet
  ## already goes through above. The overlay then fetches this lazily on
  ## first open (see `main_web.wireSearchOverlay`).
  let searchIndexJson = searchIndexToJson(buildRealSearchIndex(contentDir, manifest))
  let searchIndexHashedName = "search-index." & contentHash(searchIndexJson) & ".json"
  writeFile(outDir / searchIndexHashedName, searchIndexJson)
  hrefRewrites.add (defaultSearchIndexUrl, "/" & searchIndexHashedName)
  info "ssg_search_index_written", path = outDir / searchIndexHashedName,
    bytes = searchIndexJson.len

  ## M6 deliverable 1: sitemap.xml (all routes) + a default robots.txt.
  writeSitemapAndRobots(outDir, manifest, cfg)

  var count = 0
  for (outPath, html) in pages:
    var finalHtml = html
    for (fromHref, toHref) in hrefRewrites:
      finalHtml = finalHtml.replace(fromHref, toHref)
    createDir(outPath.parentDir)
    writeFile(outPath, finalHtml)
    inc count
    info "ssg_page_written", path = outPath, bytes = finalHtml.len
  info "ssg_complete", pages = count, outDir = outDir

  ## M11 deliverable 1: notify every `onBuildComplete` hook now that the
  ## whole static site is on disk (page count + output dir). Observation
  ## only -- an empty host is a no-op.
  applyOnBuildComplete(host, BuildInfo(pageCount: count, outDir: outDir))
  count

when isMainModule:
  ## The framework's own production build: builds the checked-in
  ## `tests/fixtures/mini-site/` under the framework's own
  ## content-agnostic defaults (M1 corrective deliverable 5). A real
  ## site's build entry (e.g. `../isonim/docs/users/src/build.nim`) calls
  ## `buildSite` with its own `contentDir`/`cfg` instead.
  let n = buildSite()
  echo "SSG: rendered ", n, " static pages into ./public/"
