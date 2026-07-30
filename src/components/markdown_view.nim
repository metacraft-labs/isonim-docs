## isonim-docs Layer 2 — rendering for the markdown block ViewModel
## (`src/core/markdown_vm.nim`, M2 deliverable 2).
##
## Block tags (`h1`..`h6`, `ol`/`ul`) and block counts are only known at
## runtime, so unlike `shell.nim`'s fixed single-route shape, these
## renderers can't be expressed as one static `ui(r): ...`/`ui: ...` DSL
## tree (the DSL's element names are literal AST identifiers, and its
## `for`/`case` support only rewires the *children* of an already-open
## element, not the element itself). Every block/inline renderer below
## is instead written directly against the generic renderer backend API
## (`createElement`/`appendChild`/`setAttribute`/`createTextNode`) for
## the Mock/browser tree side, and plain escaped string building
## (`isonim/ssr/escape`) for the SSR string side -- the same two
## interfaces the `ui` DSL macro itself compiles down to, just invoked
## directly instead of through the macro.

import std/strutils
import isonim/ssr/escape
import ../core/markdown_vm
import ../core/syntax_highlight
import ./component_registry
import ./error_boundary

export component_registry

const
  markdownBodyClass* = "docs-md-body"
  headingClass* = "docs-md-heading"
  paragraphClass* = "docs-md-paragraph"
  listClass* = "docs-md-list"
  codeFenceClass* = "docs-md-code-fence"
  codeBlockClass* = "docs-md-code-block"
  codeCopyButtonClass* = "docs-md-code-copy"
  codeCopyIdleLabel* = "Copy code"
  codeCopyCopiedLabel* = "Copied!"
  admonitionBaseClass* = "docs-md-admonition"
  tableClass* = "docs-md-table"
  tabsClass* = "docs-md-tabs"
  tablistClass* = "docs-md-tablist"
  tabClass* = "docs-md-tab"
  tabpanelClass* = "docs-md-tabpanel"
  symRefClass* = "docs-md-symref"          ## M8: a resolved [[sym:...]] link
  symRefUnknownClass* = "docs-md-symref-unknown" ## an unresolved [[sym:...]]
  componentEmbedClass* = "docs-md-component" ## M9: a live component embed wrapper
  componentUnknownClass* = "docs-md-component-unknown"
    ## M9: the typed fallback node for an unknown/unregistered component tag
  # metacraft-theme-parity M2: content components (cards / hero / button / faq).
  cardGridClass* = "docs-md-card-grid"
  cardGridCompactClass* = "docs-md-card-grid--compact"
    ## metacraft-theme-parity M6: added ALONGSIDE `cardGridClass` on a
    ## `:::cards variant="compact"` grid (the WebFlow popular-article-card
    ## look). A default `:::cards` grid never carries it, so it stays
    ## byte-for-byte the pre-M6 `class="docs-md-card-grid"`.
  cardClass* = "docs-md-card"
  cardCompactClass* = "docs-md-card--compact"
    ## metacraft-theme-parity M6: added ALONGSIDE `cardClass` on each card of a
    ## compact grid, so the theme can restyle the card title (WebFlow
    ## `.display-xs`) without touching the default card look.
  cardIconClass* = "docs-md-card-icon"
  cardBodyClass* = "docs-md-card-body"
  cardTitleClass* = "docs-md-card-title"
  cardDescriptionClass* = "docs-md-card-description"
  heroClass* = "docs-md-hero"
  heroTitleClass* = "docs-md-hero-title"
  heroSubtitleClass* = "docs-md-hero-subtitle"
  heroActionsClass* = "docs-md-hero-actions"
  buttonClass* = "docs-md-button"
  buttonSecondaryClass* = "docs-md-button-secondary"
  faqClass* = "docs-md-faq"
  faqItemClass* = "docs-md-faq-item"
  faqQuestionClass* = "docs-md-faq-question"
  faqAnswerClass* = "docs-md-faq-answer"

proc buttonClasses*(variant: string): string =
  ## The class attribute for an action button; the secondary (white)
  ## variant adds `docs-md-button-secondary` alongside the base class.
  if variant == "secondary": buttonClass & " " & buttonSecondaryClass
  else: buttonClass

proc cardGridClasses*(variant: string): string =
  ## metacraft-theme-parity M6: the class attribute for a `:::cards` grid
  ## container. A "compact" grid adds `docs-md-card-grid--compact` alongside
  ## the base class; any other/empty variant is exactly `docs-md-card-grid`
  ## (byte-for-byte the pre-M6 output).
  if variant == "compact": cardGridClass & " " & cardGridCompactClass
  else: cardGridClass

proc cardClasses*(variant: string): string =
  ## metacraft-theme-parity M6: the class attribute for one card inside a
  ## `:::cards` grid. A "compact" grid's cards add `docs-md-card--compact`;
  ## any other/empty variant is exactly `docs-md-card`.
  if variant == "compact": cardClass & " " & cardCompactClass
  else: cardClass

proc pageHasHero*(blocks: seq[Block]): bool =
  ## metacraft-theme-parity M6: true when a page's block list contains a
  ## `:::hero`. A hero marks a landing page, which the page frame renders in a
  ## WIDER content container and WITHOUT the adjacent-pages (prev/next) pager
  ## -- both derived identically from `blocks` on the SSR-string and
  ## MockRenderer/browser paths, so the two stay in lock-step (no hydration
  ## divergence). A page with no hero (every normal article) is untouched.
  for b in blocks:
    if b.kind == bkHero: return true
  false

proc tokenClass(kind: TokenKind): string =
  ## Theme-aware token span classes: `assets/style.css` maps each of
  ## these onto a `--docs-tok-*` CSS variable (light + dark), the same
  ## variable-driven theming M2's toggle already backs -- never inline
  ## colors here. `tkPlain` never reaches this proc (callers skip the
  ## `<span>` wrapper entirely for plain runs).
  case kind
  of tkPlain: ""
  of tkKeyword: "tok-keyword"
  of tkString: "tok-string"
  of tkComment: "tok-comment"
  of tkNumber: "tok-number"

proc admonitionLabel*(kind: AdmonitionKind): string =
  case kind
  of akNote: "Note"
  of akTip: "Tip"
  of akImportant: "Important" ## M3 (Gap D) -> .docs-md-admonition-important
  of akWarning: "Warning"
  of akCaution: "Caution"     ## M3 (Gap D) -> .docs-md-admonition-caution
  of akDanger: "Danger"

proc admonitionKindClass*(kind: AdmonitionKind): string =
  admonitionBaseClass & "-" & admonitionLabel(kind).toLowerAscii()

# --- MockRenderer / browser tree mode -----------------------------------

proc appendInlineSpans*[R, E](r: R; parent: E; spans: seq[InlineSpan]) =
  ## Shared inline renderer: appends each inline span (text, inline
  ## code, link, image) directly onto `parent`. Used by every block
  ## renderer below instead of duplicating this per block kind.
  for s in spans:
    case s.kind
    of ikText:
      r.appendChild(parent, r.createTextNode(s.text))
    of ikCode:
      let codeEl = r.createElement("code")
      r.appendChild(codeEl, r.createTextNode(s.text))
      r.appendChild(parent, codeEl)
    of ikLink:
      let linkEl = r.createElement("a")
      r.setAttribute(linkEl, "href", s.href)
      r.appendChild(linkEl, r.createTextNode(s.text))
      r.appendChild(parent, linkEl)
    of ikImage:
      let imgEl = r.createElement("img")
      r.setAttribute(imgEl, "src", s.href)
      r.setAttribute(imgEl, "alt", s.text)
      r.appendChild(parent, imgEl)
    of ikSymRef:
      ## M8 deliverable 2: a resolved `[[sym:...]]` renders as a link to the
      ## symbol anchor; an unresolved one renders as inline code (and is
      ## flagged by the reference checker), never crashing the render.
      if s.href.len > 0:
        let linkEl = r.createElement("a")
        r.setAttribute(linkEl, "class", symRefClass)
        r.setAttribute(linkEl, "href", s.href)
        let codeEl = r.createElement("code")
        r.appendChild(codeEl, r.createTextNode(s.text))
        r.appendChild(linkEl, codeEl)
        r.appendChild(parent, linkEl)
      else:
        let codeEl = r.createElement("code")
        r.setAttribute(codeEl, "class", symRefUnknownClass)
        r.appendChild(codeEl, r.createTextNode(s.text))
        r.appendChild(parent, codeEl)

proc renderHeading*[R, E](r: R; blk: Block): E =
  ## Builds the heading into a local (naturally `Element`-typed, not
  ## forced into the generic `E` via `result`) so `setAttribute` still
  ## resolves correctly on backends -- the real `WebRenderer` -- whose
  ## `setAttribute` only accepts the narrower `Element` type, not every
  ## renderer's broader node type; `MockRenderer` uses one node type for
  ## both, which is why this distinction didn't surface there. `E` is
  ## only reconstituted once, at the final implicit upcast on return.
  let el = r.createElement("h" & $blk.level)
  r.setAttribute(el, "class", headingClass)
  r.setAttribute(el, "id", blk.headingId)
  r.appendChild(el, r.createTextNode(blk.headingText))
  el

proc renderParagraph*[R, E](r: R; blk: Block): E =
  let el = r.createElement("p")
  r.setAttribute(el, "class", paragraphClass)
  appendInlineSpans(r, el, blk.spans)
  el

proc renderList*[R, E](r: R; blk: Block): E =
  let el = r.createElement(if blk.listKind == lkOrdered: "ol" else: "ul")
  r.setAttribute(el, "class", listClass)
  for item in blk.items:
    let li = r.createElement("li")
    appendInlineSpans(r, li, item)
    r.appendChild(el, li)
  el

proc appendHighlightedCode*[R, E](r: R; parent: E; lang, code: string) =
  ## Shared by `renderCodeFence` and any future consumer that needs
  ## highlighted spans inside an already-open element: appends each
  ## token from `syntax_highlight.tokenize` onto `parent`, wrapping only
  ## the classified kinds (keyword/string/comment/number) in a
  ## `<span class="tok-*">` -- plain runs are bare text nodes, same as
  ## an unrecognized `lang`'s single plain token.
  for tok in tokenize(lang, code):
    if tok.kind == tkPlain:
      r.appendChild(parent, r.createTextNode(tok.text))
    else:
      let span = r.createElement("span")
      r.setAttribute(span, "class", tokenClass(tok.kind))
      r.appendChild(span, r.createTextNode(tok.text))
      r.appendChild(parent, span)

proc renderCodeFence*[R, E](r: R; blk: Block): E =
  ## M3 deliverable 3: every code block is wrapped in a `codeBlockClass`
  ## div so the copy button can be absolutely positioned over the fence
  ## via CSS -- the button is the wrapper's first child, the `<pre>` its
  ## second, a structural contract `main_web.wireCodeCopyButton` walks
  ## directly (button -> nextSibling pre -> firstChild code) instead of
  ## an id lookup.
  let wrapper = r.createElement("div")
  r.setAttribute(wrapper, "class", codeBlockClass)

  let btn = r.createElement("button")
  r.setAttribute(btn, "type", "button")
  r.setAttribute(btn, "class", codeCopyButtonClass)
  r.setAttribute(btn, "aria-label", codeCopyIdleLabel)
  r.setAttribute(btn, "data-copied", "false")
  r.appendChild(btn, r.createTextNode(codeCopyIdleLabel))
  r.appendChild(wrapper, btn)

  let el = r.createElement("pre")
  r.setAttribute(el, "class", codeFenceClass)
  let codeEl = r.createElement("code")
  if blk.lang.len > 0:
    r.setAttribute(codeEl, "class", "language-" & blk.lang)
  appendHighlightedCode[R, E](r, codeEl, blk.lang, blk.code)
  r.appendChild(el, codeEl)
  r.appendChild(wrapper, el)

  wrapper

proc renderAdmonition*[R, E](r: R; blk: Block): E =
  let el = r.createElement("div")
  r.setAttribute(el, "class", admonitionBaseClass & " " & admonitionKindClass(blk.admonitionKind))
  let label = r.createElement("strong")
  r.appendChild(label, r.createTextNode(admonitionLabel(blk.admonitionKind)))
  r.appendChild(el, label)
  for para in blk.bodyParagraphs:
    let p = r.createElement("p")
    appendInlineSpans(r, p, para)
    r.appendChild(el, p)
  el

proc renderTable*[R, E](r: R; blk: Block): E =
  let el = r.createElement("table")
  r.setAttribute(el, "class", tableClass)
  let thead = r.createElement("thead")
  let headRow = r.createElement("tr")
  for h in blk.headers:
    let th = r.createElement("th")
    r.appendChild(th, r.createTextNode(h))
    r.appendChild(headRow, th)
  r.appendChild(thead, headRow)
  r.appendChild(el, thead)
  let tbody = r.createElement("tbody")
  for row in blk.rows:
    let rowEl = r.createElement("tr")
    for cell in row:
      let td = r.createElement("td")
      r.appendChild(td, r.createTextNode(cell))
      r.appendChild(rowEl, td)
    r.appendChild(tbody, rowEl)
  r.appendChild(el, tbody)
  el

proc renderButtonEl*[R, E](r: R; spec: ButtonSpec): E =
  ## metacraft-theme-parity M2: one action button as a focusable `<a>` --
  ## shared by `renderButton` (standalone) and `renderHero`.
  let a = r.createElement("a")
  r.setAttribute(a, "class", buttonClasses(spec.variant))
  r.setAttribute(a, "href", spec.href)
  r.appendChild(a, r.createTextNode(spec.label))
  a

proc renderButton*[R, E](r: R; blk: Block): E =
  renderButtonEl[R, E](r, blk.button)

proc renderCardGrid*[R, E](r: R; blk: Block): E =
  ## metacraft-theme-parity M2: the WebFlow card grid -- each card is a
  ## keyboard/focus-accessible `<a>` with an optional icon chip, a title,
  ## and a description built from the card's body paragraphs.
  let grid = r.createElement("div")
  r.setAttribute(grid, "class", cardGridClasses(blk.gridVariant))
  for card in blk.cards:
    let a = r.createElement("a")
    r.setAttribute(a, "class", cardClasses(blk.gridVariant))
    r.setAttribute(a, "href", card.href)
    if card.icon.len > 0:
      let iconWrap = r.createElement("div")
      r.setAttribute(iconWrap, "class", cardIconClass)
      let img = r.createElement("img")
      r.setAttribute(img, "src", card.icon)
      r.setAttribute(img, "alt", "")
      r.appendChild(iconWrap, img)
      r.appendChild(a, iconWrap)
    let body = r.createElement("div")
    r.setAttribute(body, "class", cardBodyClass)
    let title = r.createElement("div")
    r.setAttribute(title, "class", cardTitleClass)
    r.appendChild(title, r.createTextNode(card.title))
    r.appendChild(body, title)
    for para in card.body:
      let p = r.createElement("p")
      r.setAttribute(p, "class", cardDescriptionClass)
      appendInlineSpans(r, p, para)
      r.appendChild(body, p)
    r.appendChild(a, body)
    r.appendChild(grid, a)
  grid

proc renderHero*[R, E](r: R; blk: Block): E =
  ## metacraft-theme-parity M2: the landing hero -- an H1 title, an optional
  ## subtitle, and a row of action buttons.
  let section = r.createElement("section")
  r.setAttribute(section, "class", heroClass)
  let h1 = r.createElement("h1")
  r.setAttribute(h1, "class", heroTitleClass)
  r.appendChild(h1, r.createTextNode(blk.heroTitle))
  r.appendChild(section, h1)
  if blk.heroSubtitle.len > 0:
    let sub = r.createElement("p")
    r.setAttribute(sub, "class", heroSubtitleClass)
    r.appendChild(sub, r.createTextNode(blk.heroSubtitle))
    r.appendChild(section, sub)
  if blk.heroButtons.len > 0:
    let actions = r.createElement("div")
    r.setAttribute(actions, "class", heroActionsClass)
    for spec in blk.heroButtons:
      r.appendChild(actions, renderButtonEl[R, E](r, spec))
    r.appendChild(section, actions)
  section

proc renderFaq*[R, E](r: R; blk: Block): E =
  ## metacraft-theme-parity M2: the FAQ accordion as native, JS-free
  ## `<details>`/`<summary>` disclosures -- the accessible-by-default
  ## approach (each `<summary>` is natively a focusable, keyboard-operable
  ## button that expands its `<details>`).
  let wrap = r.createElement("div")
  r.setAttribute(wrap, "class", faqClass)
  for item in blk.faqItems:
    let details = r.createElement("details")
    r.setAttribute(details, "class", faqItemClass)
    let summary = r.createElement("summary")
    r.setAttribute(summary, "class", faqQuestionClass)
    r.appendChild(summary, r.createTextNode(item.question))
    r.appendChild(details, summary)
    let answer = r.createElement("div")
    r.setAttribute(answer, "class", faqAnswerClass)
    for para in item.answer:
      let p = r.createElement("p")
      appendInlineSpans(r, p, para)
      r.appendChild(answer, p)
    r.appendChild(details, answer)
    r.appendChild(wrap, details)
  wrap

proc renderMarkdownBlock*[R, E](r: R; blk: Block; idPath: string;
                                registry: ComponentRegistry[R, E] = nil): E

proc componentInstanceId*(idPath: string): string =
  ## Page-unique instance id for one `bkComponent` embed, derived from its
  ## `idPath` (the same dotted block position `renderMarkdownBody`/
  ## `renderTabs` thread through the tree) -- so two embeds of the same
  ## component get distinct instance ids, the seam per-embed state
  ## isolation and non-colliding DOM ids hang off.
  "docs-component-" & idPath

proc renderComponentFallback*[R, E](r: R; blk: Block): E =
  ## The TYPED fallback element for an unknown/unregistered component tag
  ## (or one the extractor already flagged via `componentError`): a small
  ## inline notice carrying the offending name, never a crash and never
  ## silent corruption.
  let el = r.createElement("div")
  r.setAttribute(el, "class", componentUnknownClass)
  r.setAttribute(el, "data-component", blk.componentName)
  let reason =
    if blk.componentError.len > 0: blk.componentError
    else: "unknown component: " & blk.componentName
  r.appendChild(el, r.createTextNode(reason))
  el

proc renderComponent*[R, E](r: R; blk: Block; idPath: string;
                            registry: ComponentRegistry[R, E]): E =
  ## Resolves a `bkComponent` node against `registry` and renders it,
  ## wrapped in the M6 error boundary so a throwing component shows the
  ## inline fallback while sibling embeds keep working. An unknown/flagged
  ## tag renders the typed fallback instead.
  if blk.componentError.len > 0 or not registry.hasComponent(blk.componentName):
    return renderComponentFallback[R, E](r, blk)
  let inst = ComponentInstance(
    name: blk.componentName,
    instanceId: componentInstanceId(idPath),
    props: blk.props,
    children: blk.componentChildren)
  let render = registry.getRender(blk.componentName)
  renderErrorBoundary[R, E](r, proc(): E = render(r, inst))

proc tabsElementId(idPath: string): string =
  ## Base id for one `bkTabs` block's tablist/panels, derived from
  ## `idPath` -- the dotted position (block index, panel index, nested
  ## block index, ...) `renderMarkdownBody`/`renderTabs` build up while
  ## walking the tree, so every tab/panel id is unique on the page even
  ## with multiple `:::tabs` blocks or nested blocks inside a panel.
  "docs-tabs-" & idPath

proc renderTabs*[R, E](r: R; blk: Block; idPath: string;
                       registry: ComponentRegistry[R, E] = nil): E =
  let tabsId = tabsElementId(idPath)
  let wrapper = r.createElement("div")
  r.setAttribute(wrapper, "class", tabsClass)

  let tablist = r.createElement("div")
  r.setAttribute(tablist, "class", tablistClass)
  r.setAttribute(tablist, "role", "tablist")
  for i, panel in blk.tabs:
    let active = i == 0
    let tabBtn = r.createElement("button")
    r.setAttribute(tabBtn, "type", "button")
    r.setAttribute(tabBtn, "id", tabsId & "-tab-" & $i)
    r.setAttribute(tabBtn, "class", tabClass)
    r.setAttribute(tabBtn, "role", "tab")
    r.setAttribute(tabBtn, "aria-selected", (if active: "true" else: "false"))
    r.setAttribute(tabBtn, "aria-controls", tabsId & "-panel-" & $i)
    r.setAttribute(tabBtn, "tabindex", (if active: "0" else: "-1"))
    r.appendChild(tabBtn, r.createTextNode(panel.title))
    r.appendChild(tablist, tabBtn)
  r.appendChild(wrapper, tablist)

  for i, panel in blk.tabs:
    let active = i == 0
    let panelEl = r.createElement("div")
    r.setAttribute(panelEl, "id", tabsId & "-panel-" & $i)
    r.setAttribute(panelEl, "class", tabpanelClass)
    r.setAttribute(panelEl, "role", "tabpanel")
    r.setAttribute(panelEl, "aria-labelledby", tabsId & "-tab-" & $i)
    r.setAttribute(panelEl, "tabindex", "0")
    if not active:
      r.setAttribute(panelEl, "hidden", "hidden")
    for j, pblk in panel.blocks:
      r.appendChild(panelEl, renderMarkdownBlock[R, E](r, pblk, idPath & "-" & $i & "-" & $j, registry))
    r.appendChild(wrapper, panelEl)

  wrapper

proc renderMarkdownBlock*[R, E](r: R; blk: Block; idPath: string;
                                registry: ComponentRegistry[R, E] = nil): E =
  case blk.kind
  of bkHeading: renderHeading[R, E](r, blk)
  of bkParagraph: renderParagraph[R, E](r, blk)
  of bkList: renderList[R, E](r, blk)
  of bkCodeFence: renderCodeFence[R, E](r, blk)
  of bkAdmonition: renderAdmonition[R, E](r, blk)
  of bkTable: renderTable[R, E](r, blk)
  of bkTabs: renderTabs[R, E](r, blk, idPath, registry)
  of bkComponent: renderComponent[R, E](r, blk, idPath, registry)
  of bkCardGrid: renderCardGrid[R, E](r, blk)
  of bkHero: renderHero[R, E](r, blk)
  of bkButton: renderButton[R, E](r, blk)
  of bkFaq: renderFaq[R, E](r, blk)

proc renderMarkdownBody*[R, E](r: R; blocks: seq[Block];
                               registry: ComponentRegistry[R, E] = nil): E =
  ## The full markdown-page tree: one container carrying every block in
  ## document order, each block dispatched to its own renderer above.
  ## `registry` (M9) resolves any `bkComponent` embeds; the default empty
  ## registry keeps every pre-M9 caller compiling unchanged and renders any
  ## stray component tag as the typed fallback.
  let el = r.createElement("div")
  r.setAttribute(el, "class", markdownBodyClass)
  for idx, blk in blocks:
    r.appendChild(el, renderMarkdownBlock[R, E](r, blk, $idx, registry))
  el

# --- SSR string mode ------------------------------------------------------

proc spansHtml*(spans: seq[InlineSpan]): string =
  for s in spans:
    case s.kind
    of ikText:
      result.add escapeHtml(s.text)
    of ikCode:
      result.add "<code>" & escapeHtml(s.text) & "</code>"
    of ikLink:
      result.add "<a href=\"" & escapeAttr(s.href) & "\">" & escapeHtml(s.text) & "</a>"
    of ikImage:
      result.add "<img src=\"" & escapeAttr(s.href) & "\" alt=\"" & escapeAttr(s.text) & "\" />"
    of ikSymRef:
      if s.href.len > 0:
        result.add "<a class=\"" & symRefClass & "\" href=\"" & escapeAttr(s.href) &
          "\"><code>" & escapeHtml(s.text) & "</code></a>"
      else:
        result.add "<code class=\"" & symRefUnknownClass & "\">" & escapeHtml(s.text) & "</code>"

proc renderHeadingHtml*(blk: Block): string =
  let tag = "h" & $blk.level
  "<" & tag & " class=\"" & headingClass & "\" id=\"" & escapeAttr(blk.headingId) & "\">" &
    escapeHtml(blk.headingText) & "</" & tag & ">"

proc renderParagraphHtml*(blk: Block): string =
  "<p class=\"" & paragraphClass & "\">" & spansHtml(blk.spans) & "</p>"

proc renderListHtml*(blk: Block): string =
  let tag = if blk.listKind == lkOrdered: "ol" else: "ul"
  result = "<" & tag & " class=\"" & listClass & "\">"
  for item in blk.items:
    result.add "<li>" & spansHtml(item) & "</li>"
  result.add "</" & tag & ">"

proc highlightedCodeHtml*(lang, code: string): string =
  ## SSR-string counterpart to `appendHighlightedCode`: wraps only the
  ## classified token kinds in `<span class="tok-*">`, HTML-escaping
  ## every token's text either way (a `tkString`/`tkComment` token can
  ## itself contain `<`/`&`, e.g. `"<x>"` or `# a & b`).
  for tok in tokenize(lang, code):
    if tok.kind == tkPlain:
      result.add escapeHtml(tok.text)
    else:
      result.add "<span class=\"" & tokenClass(tok.kind) & "\">" &
        escapeHtml(tok.text) & "</span>"

proc renderCodeFenceHtml*(blk: Block): string =
  let langAttr =
    if blk.lang.len > 0: " class=\"language-" & escapeAttr(blk.lang) & "\""
    else: ""
  "<div class=\"" & codeBlockClass & "\">" &
    "<button type=\"button\" class=\"" & codeCopyButtonClass &
      "\" aria-label=\"" & escapeAttr(codeCopyIdleLabel) &
      "\" data-copied=\"false\">" & escapeHtml(codeCopyIdleLabel) & "</button>" &
    "<pre class=\"" & codeFenceClass & "\"><code" & langAttr & ">" &
    highlightedCodeHtml(blk.lang, blk.code) & "</code></pre></div>"

proc renderAdmonitionHtml*(blk: Block): string =
  let cls = admonitionBaseClass & " " & admonitionKindClass(blk.admonitionKind)
  result = "<div class=\"" & cls & "\"><strong>" & escapeHtml(admonitionLabel(blk.admonitionKind)) & "</strong>"
  for para in blk.bodyParagraphs:
    result.add "<p>" & spansHtml(para) & "</p>"
  result.add "</div>"

proc renderTableHtml*(blk: Block): string =
  result = "<table class=\"" & tableClass & "\"><thead><tr>"
  for h in blk.headers:
    result.add "<th>" & escapeHtml(h) & "</th>"
  result.add "</tr></thead><tbody>"
  for row in blk.rows:
    result.add "<tr>"
    for cell in row:
      result.add "<td>" & escapeHtml(cell) & "</td>"
    result.add "</tr>"
  result.add "</tbody></table>"

proc renderButtonSpecHtml*(spec: ButtonSpec): string =
  ## SSR counterpart to `renderButtonEl`.
  "<a class=\"" & buttonClasses(spec.variant) & "\" href=\"" &
    escapeAttr(spec.href) & "\">" & escapeHtml(spec.label) & "</a>"

proc renderCardGridHtml*(blk: Block): string =
  ## SSR counterpart to `renderCardGrid`.
  result = "<div class=\"" & cardGridClasses(blk.gridVariant) & "\">"
  for card in blk.cards:
    result.add "<a class=\"" & cardClasses(blk.gridVariant) & "\" href=\"" & escapeAttr(card.href) & "\">"
    if card.icon.len > 0:
      result.add "<div class=\"" & cardIconClass & "\"><img src=\"" &
        escapeAttr(card.icon) & "\" alt=\"\" /></div>"
    result.add "<div class=\"" & cardBodyClass & "\">"
    result.add "<div class=\"" & cardTitleClass & "\">" & escapeHtml(card.title) & "</div>"
    for para in card.body:
      result.add "<p class=\"" & cardDescriptionClass & "\">" & spansHtml(para) & "</p>"
    result.add "</div></a>"
  result.add "</div>"

proc renderHeroHtml*(blk: Block): string =
  ## SSR counterpart to `renderHero`.
  result = "<section class=\"" & heroClass & "\">"
  result.add "<h1 class=\"" & heroTitleClass & "\">" & escapeHtml(blk.heroTitle) & "</h1>"
  if blk.heroSubtitle.len > 0:
    result.add "<p class=\"" & heroSubtitleClass & "\">" & escapeHtml(blk.heroSubtitle) & "</p>"
  if blk.heroButtons.len > 0:
    result.add "<div class=\"" & heroActionsClass & "\">"
    for spec in blk.heroButtons:
      result.add renderButtonSpecHtml(spec)
    result.add "</div>"
  result.add "</section>"

proc renderButtonHtml*(blk: Block): string =
  renderButtonSpecHtml(blk.button)

proc renderFaqHtml*(blk: Block): string =
  ## SSR counterpart to `renderFaq` -- native `<details>`/`<summary>`.
  result = "<div class=\"" & faqClass & "\">"
  for item in blk.faqItems:
    result.add "<details class=\"" & faqItemClass & "\">"
    result.add "<summary class=\"" & faqQuestionClass & "\">" & escapeHtml(item.question) & "</summary>"
    result.add "<div class=\"" & faqAnswerClass & "\">"
    for para in item.answer:
      result.add "<p>" & spansHtml(para) & "</p>"
    result.add "</div></details>"
  result.add "</div>"

proc renderMarkdownBlockHtml*(blk: Block; idPath: string;
                              registry: HtmlComponentRegistry = nil): string

proc renderComponentFallbackHtml*(blk: Block): string =
  ## SSR counterpart to `renderComponentFallback` -- the same typed inline
  ## notice for an unknown/flagged component tag.
  let reason =
    if blk.componentError.len > 0: blk.componentError
    else: "unknown component: " & blk.componentName
  "<div class=\"" & componentUnknownClass & "\" data-component=\"" &
    escapeAttr(blk.componentName) & "\">" & escapeHtml(reason) & "</div>"

proc renderComponentHtml*(blk: Block; idPath: string;
                          registry: HtmlComponentRegistry): string =
  ## SSR counterpart to `renderComponent`: resolves the `bkComponent` node
  ## against `registry`, wrapped in the M6 SSR error boundary, or the typed
  ## fallback for an unknown/flagged tag.
  if blk.componentError.len > 0 or not registry.hasComponent(blk.componentName):
    return renderComponentFallbackHtml(blk)
  let inst = ComponentInstance(
    name: blk.componentName,
    instanceId: componentInstanceId(idPath),
    props: blk.props,
    children: blk.componentChildren)
  let render = registry.getRender(blk.componentName)
  renderErrorBoundaryHtml(proc(): string = render(inst))

proc renderTabsHtml*(blk: Block; idPath: string;
                     registry: HtmlComponentRegistry = nil): string =
  let tabsId = tabsElementId(idPath)
  result = "<div class=\"" & tabsClass & "\">"
  result.add "<div class=\"" & tablistClass & "\" role=\"tablist\">"
  for i, panel in blk.tabs:
    let active = i == 0
    result.add "<button type=\"button\" id=\"" & escapeAttr(tabsId & "-tab-" & $i) &
      "\" class=\"" & tabClass & "\" role=\"tab\" aria-selected=\"" &
      (if active: "true" else: "false") & "\" aria-controls=\"" &
      escapeAttr(tabsId & "-panel-" & $i) & "\" tabindex=\"" &
      (if active: "0" else: "-1") & "\">" & escapeHtml(panel.title) & "</button>"
  result.add "</div>"
  for i, panel in blk.tabs:
    let active = i == 0
    let hiddenAttr = if active: "" else: " hidden"
    result.add "<div id=\"" & escapeAttr(tabsId & "-panel-" & $i) & "\" class=\"" &
      tabpanelClass & "\" role=\"tabpanel\" aria-labelledby=\"" &
      escapeAttr(tabsId & "-tab-" & $i) & "\" tabindex=\"0\"" & hiddenAttr & ">"
    for j, pblk in panel.blocks:
      result.add renderMarkdownBlockHtml(pblk, idPath & "-" & $i & "-" & $j, registry)
    result.add "</div>"
  result.add "</div>"

proc renderMarkdownBlockHtml*(blk: Block; idPath: string;
                              registry: HtmlComponentRegistry = nil): string =
  case blk.kind
  of bkHeading: renderHeadingHtml(blk)
  of bkParagraph: renderParagraphHtml(blk)
  of bkList: renderListHtml(blk)
  of bkCodeFence: renderCodeFenceHtml(blk)
  of bkAdmonition: renderAdmonitionHtml(blk)
  of bkTable: renderTableHtml(blk)
  of bkTabs: renderTabsHtml(blk, idPath, registry)
  of bkComponent: renderComponentHtml(blk, idPath, registry)
  of bkCardGrid: renderCardGridHtml(blk)
  of bkHero: renderHeroHtml(blk)
  of bkButton: renderButtonHtml(blk)
  of bkFaq: renderFaqHtml(blk)

proc renderMarkdownBodyHtml*(blocks: seq[Block];
                             registry: HtmlComponentRegistry = nil): string =
  result = "<div class=\"" & markdownBodyClass & "\">"
  for idx, blk in blocks:
    result.add renderMarkdownBlockHtml(blk, $idx, registry)
  result.add "</div>"
