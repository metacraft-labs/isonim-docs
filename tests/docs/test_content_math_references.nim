## Optional native integration over real content files and real KaTeX output.
## No generated-output doubles or missing-tool skips. Rendering, graph queries,
## enforcing validation and static builds receive the same explicit host.
import std/[unittest, os, strutils, tempfiles, sets]
import isonim/content/ext/math
import ../../src/core/[plugin, references, routes]
import ../../src/ssr
import ../../src/build_site

let katex = getEnv("ISONIM_KATEX")
doAssert katex.len > 0, "ISONIM_KATEX not configured; use the content-tools shell"
let host = newPluginHost(Plugin(name: "math", renderers: mathHooks(katex).renderers))

suite "real configured content graph":
  test "configured graph catches the same active math heading and table links as SSR":
    let work = createTempDir("docs-math-references-", "")
    defer: removeDir(work)
    writeFile(work / "index.md", "# Title\n\n## $x$ [lost](missing.md)\n\n| $h$ |\n| --- |\n| [lost](absent.md) |\n")
    let manifest = buildManifestFromContent(work)
    let rendered = renderRoute("/", work, manifest, host = host, strictRenderErrors = true)
    check rendered.status == 200
    check "<math " in rendered.html
    check "href=\"/missing\"" in rendered.html
    check "href=\"/absent\"" in rendered.html
    let issues = checkContentGraph(work, manifest, host = host)
    check issues.len == 2
    var targets = initHashSet[string]()
    for issue in issues:
      check issue.kind == riUnknownRoute
      check issue.sourcePath == "index.md"
      check issue.sourceLine == 1 # Existing page-granular reference provenance.
      targets.incl issue.targetHref
    check targets == toHashSet(["/missing", "/absent"])
    var enforced = false
    try: validateContentGraph(work, manifest, host = host)
    except BrokenReferenceError as e:
      enforced = true
      check e.issues.len == 2
      check "index.md:1:" in e.msg
    check enforced

    # No hooks means literal heading/table syntax in both rendering and checks.
    let plain = renderRoute("/", work, manifest, strictRenderErrors = true)
    check "<math " notin plain.html
    check "href=\"/missing\"" notin plain.html
    check "href=\"/absent\"" notin plain.html
    check checkContentGraph(work, manifest).len == 0
    validateContentGraph(work, manifest)

  test "configured static build validates with its host and preserves published bytes":
    let work = createTempDir("docs-math-build-references-", "")
    defer: removeDir(work)
    writeFile(work / "index.md", "# Title\n\n| $h$ |\n| --- |\n| [lost](absent.md) |\n")
    let output = work / "published"
    createDir(output)
    writeFile(output / "index.html", "previous published bytes")
    var enforced = false
    try: discard buildSite(outDir = output, contentDir = work, host = host)
    except BrokenReferenceError as e:
      enforced = true
      check e.issues.len == 1
      check e.issues[0].targetHref == "/absent"
    check enforced
    check readFile(output / "index.html") == "previous published bytes"

    # Lifecycle-only hosts retain the existing default build contract.
    writeFile(work / "index.md", "# Title\n\n[legacy](missing.md)\n")
    let renderOnly = newPluginHost(Plugin(onRender: proc(html: string): string =
      html & "<!-- lifecycle-only -->"))
    check buildSite(outDir = output, contentDir = work, host = renderOnly) == 1
    check "<!-- lifecycle-only -->" in readFile(output / "index.html")

    # Existing parser-only builds also keep their policy; explicit validation
    # still checks the full host when the consumer requests that gate.
    let parserOnly = newPluginHost(Plugin(preParse: proc(body: string): string =
      body.replace("legacy", "parser-only")))
    check buildSite(outDir = output, contentDir = work, host = parserOnly) == 1
    check "parser-only</a>" in readFile(output / "index.html")
    check checkContentGraph(work, buildManifestFromContent(work), host = parserOnly).len == 1

  test "configured healthy links and transformed anchors agree with SSR and build":
    let work = createTempDir("docs-math-healthy-references-", "")
    defer: removeDir(work)
    writeFile(work / "index.md", "# Title\n\n## $x$ [target](target.md#new-x)\n\n| $h$ [target](target.md#new-x) |\n| --- |\n| [target](target.md#new-x) |\n")
    writeFile(work / "target.md", "# Target\n\n## OLD\n\n[home](index.md)\n")
    let configured = newPluginHost(
      Plugin(preParse: proc(body: string): string = body.replace("## OLD", "## New $x$")),
      Plugin(renderers: mathHooks(katex).renderers))
    let manifest = buildManifestFromContent(work)
    let target = renderRoute("/target", work, manifest, host = configured, strictRenderErrors = true)
    check target.status == 200
    check "id=\"new-x\"" in target.html
    check "<math " in target.html
    check checkContentGraph(work, manifest, host = configured).len == 0
    validateContentGraph(work, manifest, host = configured)
    let output = work / "published"
    check buildSite(outDir = output, contentDir = work, host = configured) == 2
    check "<math " in readFile(output / "index.html")
    check "href=\"/target#new-x\"" in readFile(output / "index.html")

    # Explicit-link labels retain their literal semantics while containing math.
    writeFile(work / "index.md", "# Title\n\n[look $x$](target.md#missing)\n")
    let bad = checkContentGraph(work, manifest, host = configured)
    check bad.len == 1
    if bad.len == 1: check bad[0].kind == riUnknownAnchor
    # Without hooks, the target heading and its anchor remain unchanged.
    writeFile(work / "index.md", "# Title\n\n[old](target.md#old)\n")
    let plain = renderRoute("/target", work, manifest, strictRenderErrors = true)
    check "id=\"old\"" in plain.html
    check checkContentGraph(work, manifest).len == 0
    let configuredOld = checkContentGraph(work, manifest, host = configured)
    check configuredOld.len == 1
    if configuredOld.len == 1: check configuredOld[0].kind == riUnknownAnchor

  test "configured graph reports actual final body line for invalid math":
    let work = createTempDir("docs-math-reference-location-", "")
    defer: removeDir(work)
    writeFile(work / "index.md", "---\ntitle: Metadata\n---\n\n# Title\n\n\n$\\frac{$\n")
    var failure = ""
    try: validateContentGraph(work, buildManifestFromContent(work), host = host)
    except ValueError as e: failure = e.msg
    check "index.md:8: KaTeX exited with status 1" in failure
    check "ParseError" in failure

  test "tutorial math and symbol targets use the same configured graph":
    let work = createTempDir("docs-math-symbol-references-", "")
    defer: removeDir(work)
    writeFile(work / "example.nim", "proc hello*(): string = \"hello\"\n")
    writeFile(work / "tutorial.md", "# Tutorial\n\n## $x$ [[sym:hello]]\n\n| $h$ |\n| --- |\n| [[sym:hello]] |\n")
    let manifest = newRouteManifest(@[
      newRouteEntry("/tutorial", pkTutorial, meta = RouteMeta(contentPath: "tutorial.md")),
      newRouteEntry("/api", pkSymbolReference, meta = RouteMeta(contentPath: "example.nim"))])
    let rendered = renderRoute("/tutorial", work, manifest, host = host, strictRenderErrors = true)
    check rendered.status == 200
    check "<math " in rendered.html
    check "href=\"/api#sym-hello\"" in rendered.html
    check checkContentGraph(work, manifest, host = host).len == 0
    validateContentGraph(work, manifest, host = host)
    writeFile(work / "tutorial.md", "# Tutorial\n\n## $x$ [[sym:Absent]]\n")
    let issues = checkContentGraph(work, manifest, host = host)
    check issues.len == 1
    if issues.len == 1: check issues[0].kind == riUnknownSymbol

  test "explicit draft manifest keeps rendered references and target anchors in the graph":
    let work = createTempDir("docs-math-draft-references-", "")
    defer: removeDir(work)
    writeFile(work / "index.md", "# Home\n\n$x$\n")
    writeFile(work / "draft.md", "---\ndraft: true\n---\n# Draft\n\n## $x$ [lost](missing.md)\n")
    let selected = buildManifestFromContent(work, includeDrafts = true)
    let rendered = renderRoute("/draft", work, selected, host = host, strictRenderErrors = true)
    check rendered.status == 200
    check "href=\"/missing\"" in rendered.html
    let issues = checkContentGraph(work, selected, host = host)
    check issues.len == 1
    if issues.len == 1:
      check issues[0].sourcePath == "draft.md"
      check issues[0].targetHref == "/missing"
    var failed = false
    try: discard buildSite(outDir = work / "published", contentDir = work, manifest = selected, host = host)
    except BrokenReferenceError: failed = true
    check failed
    check not fileExists(work / "published/draft/index.html")

    let ordinary = buildManifestFromContent(work)
    check checkContentGraph(work, ordinary, host = host).len == 0
    check buildSite(outDir = work / "ordinary", contentDir = work, host = host) == 1
    check not fileExists(work / "ordinary/draft/index.html")

    writeFile(work / "draft.md", "---\ndraft: true\n---\n# Draft\n\n## $x$ anchor\n")
    writeFile(work / "index.md", "# Home\n\n[math $x$](draft.md#x-anchor)\n")
    check checkContentGraph(work, selected, host = host).len == 0
    validateContentGraph(work, selected, host = host)
    check buildSite(outDir = work / "published", contentDir = work, manifest = selected, host = host) == 2
    check "id=\"x-anchor\"" in readFile(work / "published/draft/index.html")
