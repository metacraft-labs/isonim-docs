## isonim-docs Layer 3 — docs page content loading.
##
## M0 keeps content parsing intentionally minimal: full Markdown handling
## (front matter, headings, code fences, admonitions, ...) is M2's job.
## The convention here is deliberately dead simple so the bootstrap
## harness has something real to exercise end to end:
##   * the first non-blank line is the page title (a leading "# " or "#"
##     is stripped, so a plain Markdown H1 file "just works" without any
##     real Markdown parsing);
##   * everything after the next blank line is the page body, kept as
##     plain text (no HTML transformation yet).
##
## `parseDocsPage` is pure (no filesystem access at all) so it is
## Tier-1-testable on both the C and JS targets. `loadDocsPage` and
## `resolveContentDir` do real `std/os` filesystem/path work; `os` isn't
## importable on the JS target (no browser filesystem), so those two are
## guarded to the C target. Every consumer of real content -- fixture
## tests via a real temp dir, and the SSR proof route via the real
## `content/` dir -- goes through `loadDocsPage`; nothing in this test
## harness mocks the filesystem.

import std/[strutils, algorithm]
when not defined(js):
  import std/os

type
  DocsPage* = object
    title*: string
    body*: string
    sourcePath*: string

proc parseDocsPage*(raw: string; sourcePath: string = ""): DocsPage =
  ## Pure parsing step -- no filesystem access, so it behaves identically
  ## on `nim c` and `nim js`. `raw` is expected to already be real file
  ## content, whether it arrived via `readFile` at runtime (C target) or
  ## `staticRead` at compile time (JS target, which has no runtime
  ## filesystem to read from).
  let lines = raw.splitLines()
  var i = 0
  while i < lines.len and lines[i].strip().len == 0:
    inc i

  var title = ""
  if i < lines.len:
    title = lines[i].strip()
    if title.startsWith("# "):
      title = title[2 .. ^1].strip()
    elif title.startsWith("#"):
      title = title[1 .. ^1].strip()
    inc i

  while i < lines.len and lines[i].strip().len == 0:
    inc i

  let bodyLines = if i < lines.len: lines[i .. ^1] else: @[]
  result = DocsPage(title: title, body: bodyLines.join("\n").strip(),
                     sourcePath: sourcePath)

proc resolveContentDir*(baseDir: string; contentDirName: string = "content"): string =
  ## Resolves the docs content directory path relative to `baseDir`
  ## (normally the project root). Pure string joining -- does not touch
  ## the filesystem, so it's safe to call (and test) on both targets,
  ## even for a directory that doesn't exist yet.
  var base = baseDir
  while base.len > 0 and base[^1] == '/':
    base = base[0 .. ^2]
  if base.len == 0:
    result = "/" & contentDirName
  else:
    result = base & "/" & contentDirName

when not defined(js):
  proc loadDocsPage*(path: string): DocsPage =
    ## Reads a real docs page file from a real filesystem path and
    ## parses it. Used by both the hermetic fixture tests (a real temp
    ## dir) and the SSR proof route (the real `content/` dir) -- the
    ## filesystem is always real here, never mocked, per the M0 harness
    ## rule.
    parseDocsPage(readFile(path), path)

  proc discoverContentSlugs*(dir: string): seq[string] =
    ## Real directory walk over `dir`, returning the slug (filename
    ## without extension) of every `.md` file found, sorted for a
    ## deterministic result. Proves content discovery isn't hardcoded to
    ## a single filename.
    for kind, path in walkDir(dir):
      if kind == pcFile and path.endsWith(".md"):
        result.add path.extractFilename.changeFileExt("")
    result.sort()

# --- M2 content loader -------------------------------------------------
##
## The M2 content loader adds what M0's `parseDocsPage` deliberately left
## out: front matter (title/description/section/order/slug/draft
## overrides), slug derivation from the file path, section-ordered
## sorting, a derived route binding, and stable source provenance (file
## path + the line the body starts at) for later broken-link reporting to
## cite. `splitFrontMatter`/`parseFrontMatter`/`parseContentEntry` are
## pure string transforms -- no filesystem access -- so they're
## Tier-1-testable on both `nim c` and `nim js`, exactly like
## `parseDocsPage`. `loadContentEntries` below is the only new
## filesystem-touching piece, and is guarded to the C target for the same
## reason `loadDocsPage` is.

type
  ContentFrontMatter* = object
    ## Optional per-page overrides parsed from a leading `---`-delimited
    ## front matter block. Every field defaults to its zero value when
    ## front matter is absent or a key isn't set, so plain M0/M1-style
    ## content files (no front matter at all) keep working unchanged.
    title*: string
    description*: string
    section*: string
    order*: int
    slug*: string
    draft*: bool
    layout*: string ## OPTIONAL page-layout selector. Empty (the default) =
                    ## the normal full docs chrome (header nav + sidebar + TOC
                    ## + footer), so every existing page is unchanged. "minimal"
                    ## opts into the auth-style minimal-chrome layout (logo only,
                    ## a centered card, no sidebar/header-nav/TOC/footer) --
                    ## threaded through the page render by `ssr.renderRoute` /
                    ## `main_web.buildRouteApp`.
    hidden*: bool   ## OPTIONAL "exclude from navigation" flag. `false` (the
                    ## default) leaves the page in the sidebar/breadcrumbs/
                    ## prev-next exactly as before. `true` keeps the page fully
                    ## ROUTED + rendered (it is still a real manifest entry) but
                    ## drops it from `navigation_vm.buildNavPages`, so a
                    ## header-linked utility page (FAQ/Support/Sign In) doesn't
                    ## clutter the docs sidebar -- matching WebFlow, whose
                    ## sidebar lists only the doc sections.
    aliases*: seq[string] ## Old site-absolute route paths (e.g.
                          ## "/old-page") that used to address this page
                          ## before a rename, kept resolvable by M3
                          ## deliverable 2's reference system
                          ## (`references.buildAliasMap`) rather than
                          ## going dead (M3 deliverable 3 wires these into
                          ## real HTTP redirects).

  ContentSource* = object
    ## Stable provenance for a loaded page: the file path relative to the
    ## content root (not an absolute, machine-specific path) and the
    ## 1-based line its body starts at -- the "file:line" pair later
    ## broken-link reporting cites.
    path*: string
    line*: int

  ContentEntry* = object
    ## One fully-parsed content page: its front matter, its parsed body
    ## (`page.title` already reflects a front matter `title:` override,
    ## if any), its derived slug/section, the route path it binds to, and
    ## its source provenance.
    front*: ContentFrontMatter
    page*: DocsPage
    slug*: string
    section*: string
    routePath*: string
    source*: ContentSource

proc splitFrontMatter*(raw: string): tuple[frontRaw: string, bodyRaw: string, bodyLine: int] =
  ## Splits a leading `---\n...\n---\n` front matter block (if present)
  ## from the rest of the content. Pure line splitting -- no assumptions
  ## about the frontmatter's contents, so it tolerates any key set.
  ## Returns the front matter text, the remaining body text, and the
  ## 1-based line the body starts at (1 when there's no front matter).
  let lines = raw.splitLines()
  if lines.len > 0 and lines[0].strip() == "---":
    var closeIdx = -1
    for i in 1 ..< lines.len:
      if lines[i].strip() == "---":
        closeIdx = i
        break
    if closeIdx >= 0:
      let frontLines = lines[1 ..< closeIdx]
      let bodyLines = if closeIdx + 1 < lines.len: lines[closeIdx + 1 .. ^1] else: @[]
      return (frontLines.join("\n"), bodyLines.join("\n"), closeIdx + 2)
  (frontRaw: "", bodyRaw: raw, bodyLine: 1)

proc splitFrontMatterList(value: string): seq[string] =
  ## Splits a comma-separated front matter value ("aliases: /a, /b") into
  ## its trimmed, non-empty parts. A bare `key:` with no value (or one
  ## that's all commas/whitespace) yields an empty seq, not `@[""]`.
  for part in value.split(','):
    let trimmed = part.strip()
    if trimmed.len > 0:
      result.add trimmed

proc parseFrontMatter*(frontRaw: string): ContentFrontMatter =
  ## Parses `key: value` lines from a front matter block. Unknown keys
  ## are ignored (forward-compatible); malformed `order`/`draft` values
  ## fall back to their zero value rather than raising, since front
  ## matter is authored by hand and shouldn't hard-fail a build over a
  ## typo the loader can simply ignore.
  for rawLine in frontRaw.splitLines():
    let line = rawLine.strip()
    if line.len == 0:
      continue
    let colonIdx = line.find(':')
    if colonIdx < 0:
      continue
    let key = line[0 ..< colonIdx].strip()
    let value = line[colonIdx + 1 .. ^1].strip()
    case key
    of "title": result.title = value
    of "description": result.description = value
    of "section": result.section = value
    of "slug": result.slug = value
    of "order":
      try: result.order = parseInt(value)
      except ValueError: discard
    of "draft":
      try: result.draft = parseBool(value)
      except ValueError: discard
    of "layout": result.layout = value.toLowerAscii()
    of "hidden":
      try: result.hidden = parseBool(value)
      except ValueError: discard
    of "aliases": result.aliases = splitFrontMatterList(value)
    else: discard

proc deriveSlug*(relPath: string; front: ContentFrontMatter): string =
  ## The slug a page is addressed by: an explicit front matter `slug:`
  ## wins, otherwise the file's own basename with its `.md` extension
  ## stripped. Works on forward-slash-joined relative paths only (never
  ## an OS path), so it's the same on every target.
  if front.slug.len > 0:
    return front.slug
  var base = relPath
  let slashIdx = base.rfind('/')
  if slashIdx >= 0:
    base = base[slashIdx + 1 .. ^1]
  if base.endsWith(".md"):
    base = base[0 ..< base.len - 3]
  base

proc deriveSection*(relPath: string; front: ContentFrontMatter): string =
  ## The section a page belongs to: an explicit front matter `section:`
  ## wins, otherwise the page's own parent directory (relative to the
  ## content root), so a plain nested layout like `guide/foo.md` doesn't
  ## need to repeat `section: guide` in every file's front matter.
  if front.section.len > 0:
    return front.section
  let slashIdx = relPath.rfind('/')
  if slashIdx >= 0: relPath[0 ..< slashIdx] else: ""

proc deriveRoutePath*(section, slug: string): string =
  ## The route path a page binds to: a bare content root ("" section)
  ## with slug "index" is the site root "/"; an "index" page inside a
  ## section is that section's own root; everything else is
  ## "/section/slug" (or just "/slug" with no section).
  if slug == "index":
    (if section.len == 0: "/" else: "/" & section)
  else:
    (if section.len == 0: "/" & slug else: "/" & section & "/" & slug)

proc parseContentEntry*(raw: string; relPath: string): ContentEntry =
  ## The pure per-file parsing step `loadContentEntries` calls for every
  ## real file it finds: splits front matter, parses it, parses the
  ## remaining body with the same `parseDocsPage` M0/M1 content already
  ## uses (a front matter `title:` overrides the body's own leading
  ## heading, when set), and derives slug/section/route binding plus
  ## source provenance. No filesystem access, so it's exercisable on
  ## both targets with an in-memory `raw` string.
  let (frontRaw, bodyRaw, bodyLine) = splitFrontMatter(raw)
  let front = parseFrontMatter(frontRaw)
  var page = parseDocsPage(bodyRaw, relPath)
  if front.title.len > 0:
    page.title = front.title
  let slug = deriveSlug(relPath, front)
  let section = deriveSection(relPath, front)
  ContentEntry(front: front, page: page, slug: slug, section: section,
               routePath: deriveRoutePath(section, slug),
               source: ContentSource(path: relPath, line: bodyLine))

proc sortContentEntries*(entries: var seq[ContentEntry]) =
  ## The one stable content reading order every entry list gets sorted
  ## into, whether it came from a real directory walk (`loadContentEntries`,
  ## C target) or a compile-time-embedded content table (the JS mount
  ## entry's own auto-discovery default, which has no real filesystem to
  ## walk): (section, front-matter order, slug), so a directory-derived
  ## and an embedded-content-derived manifest never disagree on ordering
  ## for the same content set.
  entries.sort(proc(a, b: ContentEntry): int =
    if a.section != b.section: return cmp(a.section, b.section)
    if a.front.order != b.front.order: return cmp(a.front.order, b.front.order)
    cmp(a.slug, b.slug))

when not defined(js):
  proc loadContentEntries*(dir: string; includeDrafts: bool = false): seq[ContentEntry] =
    ## Real recursive directory walk over `dir` (a hermetic fixture temp
    ## dir in tests, the real `content/` dir in production): parses every
    ## `.md` file into a `ContentEntry`, filters out drafts unless
    ## `includeDrafts` is set, and returns them sorted by (section, order,
    ## slug) so section ordering is deterministic regardless of
    ## filesystem enumeration order.
    var entries: seq[ContentEntry] = @[]
    for path in walkDirRec(dir):
      if path.endsWith(".md"):
        let relPath = path.relativePath(dir)
        let entry = parseContentEntry(readFile(path), relPath)
        if includeDrafts or not entry.front.draft:
          entries.add entry
    sortContentEntries(entries)
    entries

  proc loadContentEntry*(dir: string; relPath: string): ContentEntry =
    ## Loads and parses the single real content file at `dir/relPath` --
    ## the one-file counterpart to `loadContentEntries`' directory walk,
    ## used by route rendering (`RouteMeta.contentPath` binds one route
    ## to exactly one content file, not a whole directory).
    parseContentEntry(readFile(dir / relPath), relPath)
