## Consumer rendering/Signal-copy tests use validated literal fragments to test
## the pure C/JS handoff. Real CLI positives belong to core's math/diagram tests;
## this is not a substitute backend for those tests.
import std/[unittest, strutils, tables, sets]
import isonim/core/signals
import isonim/testing/mock_dom
import isonim/content/[markdown, directives]
import ../../src/components/markdown_view
import ../../src/core/[plugin, content, references]
import ./helpers/mock_tree

let renderers = ContentRenderers(
  math: proc(tex: string; display: bool; location: SourceLocation): ContentFragment =
    mathFragment("<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mi>x</mi></math>"),
  diagram: proc(language, source: string; location: SourceLocation): ContentFragment =
    diagramFragment("<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M0 0L1 1\" fill=\"none\"></path></svg>"))

suite "shared build time fragments in docs":
  test "content renderer detection excludes established parser and lifecycle plugins":
    check not PluginHost().hasContentRenderers
    check not newPluginHost(Plugin(name: "named-only")).hasContentRenderers
    check not newPluginHost(Plugin(onRender: proc(html: string): string = html)).hasContentRenderers
    check not newPluginHost(Plugin(preParse: proc(body: string): string = body)).hasContentRenderers
    check not newPluginHost(Plugin(postParse: proc(doc: var MarkdownDoc) = discard)).hasContentRenderers
    check not newPluginHost(Plugin(directives: @[DirectiveRegistration(name: "custom")])).hasContentRenderers
    check newPluginHost(Plugin(renderers: ContentRenderers(math: renderers.math))).hasContentRenderers
    check newPluginHost(Plugin(renderers: ContentRenderers(diagram: renderers.diagram))).hasContentRenderers
  test "validated fragments survive Signal copying into SSR and tree renderers":
    let doc = parseMarkdownDocWithHooks(@[ParseHooks(renderers: renderers)],
      "# $x$\n\n[$y$](https://example.test)\n\n| h |\n| --- |\n| $z$ |\n\n```d2\na -> b\n```")
    let state = createSignal(doc)
    let copied = state.val
    let html = renderMarkdownBodyHtml(copied.blocks)
    check html.count("<math ") == 3
    check html.count("<svg ") == 1
    check "language-d2" notin html
    let r = MockRenderer()
    let tree = renderMarkdownBody[MockRenderer, MockNode](r, copied.blocks)
    # MockRenderer records setInnerHtml bytes without parsing them. The real
    # WebRenderer consumes those same validated bytes through innerHTML.
    check tree.textContent.count("<math ") == 3
    check tree.textContent.count("<svg ") == 1
  test "docs plugins delegate the optional renderers":
    var host: PluginHost
    host.registerPlugin(Plugin(name: "content", renderers: renderers))
    let doc = host.parseMarkdownDocWithPlugins("$x$", "plugin.md")
    check "<math " in renderMarkdownBodyHtml(doc.blocks)
  test "reference checking covers links and symbols in rendered math headings":
    let doc = parseMarkdownDocWithHooks(@[ParseHooks(renderers: renderers)],
      "# $x$ [lost](missing.md) [[sym:Missing]]", "math.md")
    let issues = checkPageReferences(doc, ContentSource(path: "math.md", line: 2),
      "/math", initHashSet[string](), initTable[string, HashSet[string]]())
    check issues.len == 2
    var kinds: set[ReferenceIssueKind]
    for issue in issues: kinds.incl issue.kind
    check kinds == {riUnknownRoute, riUnknownSymbol}
  test "math table header and cell references are checked":
    let doc = parseMarkdownDocWithHooks(@[ParseHooks(renderers: renderers)],
      "| $x$ [lost](missing.md) |\n| --- |\n| [[sym:Missing]] |", "table.md")
    let issues = checkPageReferences(doc, ContentSource(path: "table.md", line: 4),
      "/table", initHashSet[string](), initTable[string, HashSet[string]]())
    check issues.len == 2
    var kinds: set[ReferenceIssueKind]
    for issue in issues: kinds.incl issue.kind
    check kinds == {riUnknownRoute, riUnknownSymbol}
  test "body coordinates include title and blank trimming without moving page provenance":
    let entry = parseContentEntry("---\ntitle: Meta\n---\n\n# Title\n\n\n$x$\n", "coordinates.md")
    check entry.source.line == 4
    check entry.page.bodyLine == 8
    check entry.page.body == "$x$"
