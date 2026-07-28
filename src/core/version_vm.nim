## isonim-docs Layer 3 — the documentation-versioning ViewModel (M10
## deliverable 2). Pure data + pure resolution logic, zero platform/CSS/DOM
## imports, so it is headless-testable on both `nim c` and `nim js` exactly
## like `tutorial_vm.nim`/`theme_vm.nim`.
##
## A versioned docs site serves N snapshots of its content side by side. One
## of them is the LATEST (the canonical, unprefixed site: `/guide/x`); every
## older snapshot lives behind a `/vX.Y/` route prefix (`/v1.2/guide/x`) and
## carries its OWN, isolated content tree and search index, plus an
## "outdated version" banner steering the reader back to latest. This module
## owns exactly four content-agnostic pieces of that:
##   * PARSING a `/vX.Y/`-prefixed path into `(versionId, basePath)` and back
##     (`splitVersionPrefix`/`withVersionPrefix`), so the router can strip the
##     prefix, match `basePath` against that version's manifest, and links can
##     re-prefix a page for a chosen version;
##   * RESOLVING a request path to the version it targets (`resolveVersionedPath`)
##     -- an unprefixed path is the latest, a known prefix is that version, an
##     unknown prefix is flagged (`known=false`) for the caller to 404;
##   * ISOLATION path derivation: which content dir (`versionContentDir`) and
##     which search-index url (`versionedSearchIndexPath`) a given version
##     reads from, so no version ever bleeds content or search hits into
##     another;
##   * the derived UI state the shell renders: the "outdated" BANNER
##     (`buildVersionBanner`, shown only on a known non-latest version) and the
##     version SELECTOR (`buildVersionSelector`, one option per version linking
##     to the same page under that version).
##
## The VM never touches a filesystem or a manifest of its own -- it is fed an
## already-assembled `VersionCatalog` (from consumer config) and, for route
## resolution, hands the caller a `basePath` to match against whichever
## per-version `RouteManifest` the caller built. That keeps it content-agnostic
## and dual-target: the actual per-version content walk lives in the C-target
## SSR entry (`src/ssr.nim`), the pure decision logic lives here.

import ./routes

type
  VersionInfo* = object
    id*: string     ## Version id as it appears in the route prefix: the "1.2"
                    ## in `/v1.2/...` (prefix is `versionPrefix(id)` == "/v1.2").
                    ## Free-form beyond "starts with a digit"; the framework
                    ## never parses it as a number, so "1.2", "2", "0.9-rc" all
                    ## work -- ordering is the catalog's declared order, not a
                    ## numeric sort.
    label*: string  ## Display label shown in the version selector, e.g.
                    ## "v1.2 (stable)". Falls back to `"v" & id` when empty.

  VersionCatalog* = object
    ## The consumer-declared set of documentation versions. `versions` is in
    ## display order (newest first is the convention, but nothing here depends
    ## on it); `latestId` names the one served canonically/unprefixed. The
    ## zero-value `VersionCatalog()` means "versioning disabled" -- the whole
    ## feature is opt-in, so an unversioned site keeps its exact pre-M10 shape.
    versions*: seq[VersionInfo]
    latestId*: string

  VersionResolution* = object
    ## The outcome of resolving a request path against a catalog.
    versionId*: string ## The version the path targets: the parsed prefix, or
                       ## `catalog.latestId` when the path is unprefixed.
    basePath*: string  ## The path with any `/vX.Y/` prefix stripped -- what the
                       ## caller matches against that version's `RouteManifest`.
    prefixed*: bool    ## Whether the incoming path actually carried a version
                       ## prefix (false => the canonical latest site).
    known*: bool       ## Whether `versionId` is a declared catalog version. A
                       ## prefixed-but-unknown version is `known=false` -- the
                       ## caller should 404 rather than serve latest silently.
    outdated*: bool    ## True only for a KNOWN, non-latest version -- the exact
                       ## condition the "outdated" banner renders on.

  VersionBannerViewModel* = object
    ## Derived state for the "you're viewing an old version" banner. `show`
    ## gates rendering entirely, so the shell renders nothing on latest.
    show*: bool
    versionId*: string
    latestId*: string
    latestUrl*: string ## Link to the SAME page on the latest (canonical,
                       ## unprefixed) version -- i.e. `basePath`.
    message*: string

  VersionSelectorOption* = object
    id*: string
    label*: string
    url*: string     ## Route to the current page under this version.
    current*: bool   ## Whether this is the version currently being viewed.

  VersionSelectorViewModel* = object
    options*: seq[VersionSelectorOption]
    currentId*: string

# --- Version id <-> route prefix ---------------------------------------

proc versionPrefix*(id: string): string =
  ## The route-path prefix a version's pages live behind: "1.2" -> "/v1.2".
  ## The one place the `/vX.Y/` shape is minted, so parsing and building can
  ## never disagree.
  "/v" & id

proc splitVersionPrefix*(path: string): tuple[versionId, basePath: string] =
  ## Splits a request path into `(versionId, basePath)`: "/v1.2/guide/x" ->
  ## ("1.2", "/guide/x"), "/v1.2" -> ("1.2", "/"), and an unprefixed
  ## "/guide/x" -> ("", "/guide/x"). A prefix is recognised only when the
  ## first segment is `v` immediately followed by a digit, so a real content
  ## page literally named "/verbose" is never mistaken for a version. Both
  ## halves come back normalized (`routes.normalizeRoutePath`).
  let p = normalizeRoutePath(path)
  if p.len >= 3 and p[0] == '/' and p[1] == 'v' and p[2] in {'0'..'9'}:
    var i = 2
    while i < p.len and p[i] != '/':
      inc i
    let id = p[2 ..< i]
    let rest = if i < p.len: p[i .. ^1] else: "/"
    (id, normalizeRoutePath(rest))
  else:
    ("", p)

proc withVersionPrefix*(versionId, basePath: string): string =
  ## Re-attaches a version prefix to a base path: ("1.2", "/guide/x") ->
  ## "/v1.2/guide/x"; ("1.2", "/") -> "/v1.2". The inverse of
  ## `splitVersionPrefix`, so a round trip through both is the identity.
  let b = normalizeRoutePath(basePath)
  if b == "/": versionPrefix(versionId)
  else: versionPrefix(versionId) & b

# --- Catalog queries ---------------------------------------------------

proc isKnownVersion*(catalog: VersionCatalog; id: string): bool =
  ## Whether `id` is one of the catalog's declared versions.
  for v in catalog.versions:
    if v.id == id: return true
  false

proc isLatest*(catalog: VersionCatalog; id: string): bool =
  ## Whether `id` is the catalog's canonical latest version.
  id == catalog.latestId

proc versionLabel*(v: VersionInfo): string =
  ## The selector-visible label, defaulting to "v" & id when none was given.
  if v.label.len > 0: v.label else: "v" & v.id

# --- Resolution --------------------------------------------------------

proc resolveVersionedPath*(catalog: VersionCatalog; path: string): VersionResolution =
  ## Resolves `path` against `catalog`. An unprefixed path is the latest
  ## (`versionId = latestId`, `prefixed = false`, never `outdated`); a prefixed
  ## path names its own version, `known` iff the catalog declares it, and
  ## `outdated` iff it is known and not the latest. Never raises; the caller
  ## decides what an unknown (`known=false`) version does (typically a 404).
  let (rawId, base) = splitVersionPrefix(path)
  let prefixed = rawId.len > 0
  let id = if prefixed: rawId else: catalog.latestId
  let known = isKnownVersion(catalog, id)
  VersionResolution(versionId: id, basePath: base, prefixed: prefixed,
                    known: known, outdated: known and not isLatest(catalog, id))

# --- Content + search-index isolation ----------------------------------

proc versionContentDir*(baseContentDir: string; catalog: VersionCatalog;
                        versionId: string): string =
  ## Which content directory a version reads from: the latest reads the site's
  ## own `baseContentDir` (the canonical tree), every older version reads an
  ## isolated snapshot in a `versions/v<id>/` directory that is a SIBLING of
  ## `baseContentDir` (Docusaurus-style `versioned_docs/`), NOT nested inside
  ## it -- so the latest content walk never sees a snapshot and no two versions
  ## ever share content. Pure string work (no `std/os`) to stay dual-target;
  ## the actual directory walk is the C-target caller's job.
  if isLatest(catalog, versionId): baseContentDir
  else:
    var b = baseContentDir
    while b.len > 1 and b[^1] == '/': b = b[0 ..< b.len - 1]
    var slash = -1
    for i in 0 ..< b.len:
      if b[i] == '/': slash = i
    let parent = if slash >= 0: b[0 ..< slash] else: "."
    parent & "/versions/v" & versionId

proc versionedSearchIndexPath*(catalog: VersionCatalog; versionId, latestPath: string): string =
  ## Which search-index artifact url a version's search box fetches: the latest
  ## keeps the site-wide `latestPath` (e.g. "/search-index.json"), every older
  ## version fetches a version-prefixed one ("/v1.2/search-index.json") built
  ## from that version's isolated content -- so searching an old version never
  ## returns latest's pages, and vice versa.
  if isLatest(catalog, versionId): latestPath
  else:
    let lp = if latestPath.len > 0 and latestPath[0] == '/': latestPath else: "/" & latestPath
    versionPrefix(versionId) & lp

# --- Derived UI: banner + selector -------------------------------------

proc buildVersionBanner*(catalog: VersionCatalog; res: VersionResolution): VersionBannerViewModel =
  ## The "outdated version" banner state: shown ONLY on a known, non-latest
  ## version (`res.outdated`), linking back to the same page on latest. On
  ## latest -- or an unknown version the caller is about to 404 -- it's the
  ## hidden zero-value, so the shell renders no banner at all.
  if res.outdated:
    VersionBannerViewModel(show: true, versionId: res.versionId,
      latestId: catalog.latestId, latestUrl: res.basePath,
      message: "You are viewing v" & res.versionId &
        ", which is not the latest version.")
  else:
    VersionBannerViewModel()

proc versionUrl*(catalog: VersionCatalog; versionId, basePath: string): string =
  ## The route to `basePath` under `versionId`: the canonical, unprefixed path
  ## for the latest, a `/vX.Y/`-prefixed path for any older version. The one
  ## rule both the selector and any deep link switching versions go through.
  if isLatest(catalog, versionId): normalizeRoutePath(basePath)
  else: withVersionPrefix(versionId, basePath)

proc buildVersionSelector*(catalog: VersionCatalog; res: VersionResolution): VersionSelectorViewModel =
  ## One selector option per catalog version, each linking to the CURRENT page
  ## (`res.basePath`) under that version, with the viewed version marked
  ## `current`. Empty when the catalog declares no versions (feature disabled).
  var opts: seq[VersionSelectorOption] = @[]
  for v in catalog.versions:
    opts.add VersionSelectorOption(id: v.id, label: versionLabel(v),
      url: versionUrl(catalog, v.id, res.basePath),
      current: v.id == res.versionId)
  VersionSelectorViewModel(options: opts, currentId: res.versionId)

# --- Builders ----------------------------------------------------------

proc newVersionInfo*(id: string; label: string = ""): VersionInfo =
  VersionInfo(id: id, label: label)

proc newVersionCatalog*(versions: seq[VersionInfo]; latestId: string): VersionCatalog =
  ## Assembles a catalog and names its latest version. `latestId` should be one
  ## of `versions`' ids; if it isn't, every version simply resolves as
  ## non-latest (there is no canonical page), which the caller can detect via
  ## `isKnownVersion(catalog, catalog.latestId)`.
  VersionCatalog(versions: versions, latestId: latestId)
