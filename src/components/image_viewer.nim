## isonim-docs Layer 2 — full-viewport viewing for content images.
##
## A large screenshot in a docs page is rendered into the content column,
## which is far narrower than the image really is (`assets/style.css`
## constrains every `img` to `max-width: 100%`), so the detail in it is
## unreadable. This module adds the missing half: when — and ONLY when —
## an image is actually being displayed smaller than it is, the page
## offers an affordance to view it at full viewport size, in an overlay
## that can be dismissed by a visible close control, `Escape`, or a click
## on the backdrop.
##
## It has two halves, in the two places the framework already puts them:
##
## * **Markup** (`renderImageFigure`/`renderImageFigureHtml`, used by
##   `components/markdown_view`'s `ikImage` span on BOTH renderer
##   backends): an inline `docs-md-figure` wrapper holding the `<img>`
##   and an affordance `<a>` pointing at the image file itself. Being a
##   plain link is what makes this PROGRESSIVE ENHANCEMENT: with no JS at
##   all the page still renders the image and still offers a working
##   route to the full-size file. The wrapper is a `<span>`, not a
##   `<figure>`/`<div>`, because a content image is an INLINE span inside
##   a `<p>` (see `markdown_vm.InlineSpan`) and block content inside a
##   paragraph is invalid HTML that browsers re-parent.
##
## * **Behaviour** (`imageViewerScriptBody`, emitted at the end of every
##   page's `<body>` by `ssr.renderRoute`): a small, self-contained,
##   hand-written client script — the same idiom, and the same reasons,
##   as `theme_toggle.renderThemeBootstrapHtml`'s no-flash bootstrap. It
##   is deliberately NOT part of `main_web.nim`'s Nim client bundle:
##   every consumer of this framework must inherit this behaviour without
##   editing its own client entry (a real consumer — the CodeTracer book —
##   ships its own hand-written `src/main.nim` mount that binds only to
##   the chrome it knows about), and a consumer that ships NO client
##   bundle at all (`DocsConfig.appScriptHref` is empty by default) must
##   get it too. Emitting it from the SSR path is the only seam that
##   reaches all of them. Its exact body is hashed into the CSP
##   `script-src` by `shell.pageInlineScriptBodies`, so a strict,
##   hash-based policy whitelists precisely this script.
##
## "Is this image downscaled?" is a RENDERED-SIZE fact — the natural width
## of the decoded image versus the width the layout gave it — so it can
## only be answered on the client, after the image has loaded, and it
## changes when the viewport changes. The script therefore OWNS the
## `data-zoomable` attribute: SSR never guesses it, the CSS treats
## "absent" as the no-JS state (affordance visible, acting as a plain
## link), `"false"` as measured-and-not-downscaled (no affordance at all —
## an expand control that does nothing is worse than none), and `"true"`
## as measured-and-downscaled (affordance shown, image itself clickable).
##
## Pan and zoom inside the overlay are deliberately NOT implemented: the
## scope here is "view it large, close it again", and a pan/zoom surface
## is a different feature with its own gesture, keyboard and a11y design.

import std/strutils
import isonim/ssr/escape

const
  imageFigureClass* = "docs-md-figure"
    ## The inline wrapper around one content image + its affordance.
  imageClass* = "docs-md-image"
    ## The content `<img>` itself (chrome images -- logos, card icons --
    ## deliberately do NOT carry this class and get no affordance).
  imageExpandClass* = "docs-md-image-expand"
    ## The affordance: an `<a>` to the image file, upgraded by the client
    ## script into an in-page "open the viewer" control.
  imageZoomableAttr* = "data-zoomable"
    ## Owned by the client script; see this module's docstring for the
    ## absent/"false"/"true" tri-state and what each means.
  imageExpandGlyph* = "⛶"
    ## U+26F6 SQUARE FOUR CORNERS -- the conventional "view full size"
    ## mark. Purely decorative: the control's accessible name comes from
    ## its `aria-label`.
  imageExpandLabelBase* = "View image full size"

  imageOverlayClass* = "docs-image-overlay"
  imageOverlayImageClass* = "docs-image-overlay-image"
  imageOverlayCaptionClass* = "docs-image-overlay-caption"
  imageOverlayCloseClass* = "docs-image-overlay-close"
  imageOverlayOpenAttr* = "data-open"
  imageViewerRootOpenAttr* = "data-docs-image-viewer-open"
    ## Set on `<html>` while the viewer is open; `assets/style.css` hangs
    ## the background-scroll lock off it (the same "state as a data
    ## attribute on the document root" idiom as the theme's
    ## `theme_vm.themeAttrName`).
  imageViewerDialogLabel* = "Image viewer"
  imageViewerCloseLabel* = "Close image viewer"
  imageViewerScriptId* = "docs-image-viewer"

const imageViewerRuntimeClasses* = [
  ## CSS-purge SAFELIST: the overlay is BUILT BY THE CLIENT, so none of
  ## these classes ever appears in a static page's HTML and the SSG's
  ## HTML-scanning purge (`core/asset_pipeline.purgeCss`) would strip
  ## their rules, shipping an unstyled full-screen overlay. `build_site`
  ## folds this set into the purge's `usedClasses`, exactly as it already
  ## does for `search_view.searchRuntimeClasses`.
  imageOverlayClass,
  imageOverlayImageClass,
  imageOverlayCaptionClass,
  imageOverlayCloseClass]

proc imageExpandLabel*(alt: string): string =
  ## The affordance's accessible name. The image's own `alt` text carries
  ## through so a screen-reader user is told WHICH image the control opens
  ## when a page has several.
  if alt.len > 0: imageExpandLabelBase & ": " & alt else: imageExpandLabelBase

# --- markup: MockRenderer / browser tree mode -----------------------------

proc appendImageFigure*[R, E](r: R; parent: E; src, alt: string) =
  ## Appends one content image (wrapper + `<img>` + affordance) onto
  ## `parent`. Kept in lock-step, element for element and attribute for
  ## attribute, with `renderImageFigureHtml` below -- the two backends
  ## must build the identical tree or `hydrating_renderer`'s structural
  ## walk would fail to reuse the SSR nodes (see
  ## `test_hydration_browser_mount.nim`).
  let wrap = r.createElement("span")
  r.setAttribute(wrap, "class", imageFigureClass)

  let imgEl = r.createElement("img")
  r.setAttribute(imgEl, "class", imageClass)
  r.setAttribute(imgEl, "src", src)
  r.setAttribute(imgEl, "alt", alt)
  r.appendChild(wrap, imgEl)

  ## `target="_blank"` is what makes the no-JS route sane (the full-size
  ## file opens without losing the reader's place in the page) and, as a
  ## bonus, keeps `main_web.qualifiesForSoftNav` from ever intercepting
  ## this link as an in-site soft navigation.
  let expand = r.createElement("a")
  r.setAttribute(expand, "class", imageExpandClass)
  r.setAttribute(expand, "href", src)
  r.setAttribute(expand, "target", "_blank")
  r.setAttribute(expand, "rel", "noopener noreferrer")
  r.setAttribute(expand, "aria-label", imageExpandLabel(alt))
  r.appendChild(expand, r.createTextNode(imageExpandGlyph))
  r.appendChild(wrap, expand)

  r.appendChild(parent, wrap)

# --- markup: SSR string mode ----------------------------------------------

proc renderImageFigureHtml*(src, alt: string): string =
  ## SSR counterpart to `appendImageFigure`. Every author-supplied value
  ## (`src`, `alt`) is attribute-escaped, so a hostile alt/src can break
  ## out of neither the attribute nor the element.
  "<span class=\"" & imageFigureClass & "\">" &
    "<img class=\"" & imageClass & "\" src=\"" & escapeAttr(src) &
      "\" alt=\"" & escapeAttr(alt) & "\" />" &
    "<a class=\"" & imageExpandClass & "\" href=\"" & escapeAttr(src) &
      "\" target=\"_blank\" rel=\"noopener noreferrer\" aria-label=\"" &
      escapeAttr(imageExpandLabel(alt)) & "\">" & escapeHtml(imageExpandGlyph) & "</a>" &
  "</span>"

# --- behaviour: the client script -----------------------------------------

proc jsString(s: string): string =
  ## Single-quoted JS string literal for the fixed, framework-controlled
  ## constants this script embeds (class names, labels) -- never
  ## content-supplied text. Same minimal escaping, for the same reason, as
  ## `theme_toggle.escapeJsString`.
  result.add '\''
  for c in s:
    case c
    of '\'': result.add "\\'"
    of '\\': result.add "\\\\"
    of '\n': result.add "\\n"
    else: result.add c
  result.add '\''

proc imageViewerScriptBody*(): string =
  ## The raw JS body of the image viewer -- the exact text between the
  ## `<script>` tags, split out from `renderImageViewerScriptHtml` so the
  ## CSP manager (`core/csp.nim`) hashes the identical bytes a browser
  ## hashes when matching a `'sha256-...'` script-src source (the same
  ## split, for the same reason, as `theme_toggle.themeBootstrapScriptBody`).
  ##
  ## Written in defensive ES5 and wrapped in `try`/`catch` end to end: a
  ## docs page must never fail to render or navigate because an
  ## enhancement script hit an unsupported API. Every capability it uses
  ## beyond the DOM basics (`requestAnimationFrame`, `MutationObserver`,
  ## `Element.closest`) is feature-detected, and its absence degrades to
  ## "the affordance stays a plain link to the image file".
  "(function(){\n" &
  "try{\n" &
  "if(typeof document==='undefined'||!document.addEventListener){return;}\n" &
  "var FIG=" & jsString(imageFigureClass) & ";\n" &
  "var IMG=" & jsString(imageClass) & ";\n" &
  "var EXP=" & jsString(imageExpandClass) & ";\n" &
  "var ZOOM=" & jsString(imageZoomableAttr) & ";\n" &
  "var OPEN=" & jsString(imageOverlayOpenAttr) & ";\n" &
  "var LOCK=" & jsString(imageViewerRootOpenAttr) & ";\n" &
  "var DIALOG_LABEL=" & jsString(imageViewerDialogLabel) & ";\n" &
  "var CLOSE_LABEL=" & jsString(imageViewerCloseLabel) & ";\n" &
  "var overlay=null,overlayImg=null,overlayCaption=null,closeBtn=null,lastFocused=null;\n" &
  "var savedScrollX=0,savedScrollY=0;\n" &
  # --- measurement: the ONE fact that decides whether an affordance exists
  "function figureImage(fig){return fig.querySelector('.'+IMG);}\n" &
  "function measure(fig){\n" &
  "  var img=figureImage(fig);\n" &
  "  if(!img){return;}\n" &
  "  var natural=img.naturalWidth||0;\n" &
  "  var shown=img.clientWidth||0;\n" &
  # Still loading (natural 0) or not laid out / inside a hidden tab panel
  # (shown 0) => NOT KNOWN to be downscaled; re-measured on load/resize.
  # The 1px slack absorbs sub-pixel layout rounding.
  "  var zoomable=(natural>0&&shown>0&&natural>shown+1)?'true':'false';\n" &
  "  if(fig.getAttribute(ZOOM)!==zoomable){fig.setAttribute(ZOOM,zoomable);}\n" &
  "}\n" &
  "function measureAll(){\n" &
  "  var list=document.querySelectorAll('.'+FIG);\n" &
  "  for(var i=0;i<list.length;i++){measure(list[i]);}\n" &
  "}\n" &
  "var pending=false;\n" &
  "function scheduleMeasure(){\n" &
  "  if(pending){return;}\n" &
  "  pending=true;\n" &
  "  var run=function(){pending=false;measureAll();};\n" &
  "  if(typeof requestAnimationFrame==='function'){requestAnimationFrame(run);}\n" &
  "  else{setTimeout(run,16);}\n" &
  "}\n" &
  # --- the overlay: built lazily, once, on the first open
  "function isOpen(){return !!overlay&&overlay.getAttribute(OPEN)==='true';}\n" &
  "function closeViewer(){\n" &
  "  if(!isOpen()){return;}\n" &
  "  overlay.setAttribute(OPEN,'false');\n" &
  "  overlay.hidden=true;\n" &
  "  overlayImg.removeAttribute('src');\n" &
  "  try{document.documentElement.removeAttribute(LOCK);}catch(e){}\n" &
  "  var target=lastFocused;\n" &
  "  lastFocused=null;\n" &
  # Closing must put the reader back exactly where they were reading. Two
  # things can move them, and both are undone here: refocusing the affordance
  # would scroll it into view (hence `preventScroll`), and releasing an
  # `overflow:hidden` scroll lock is known to drop the document's scroll
  # offset on some engines/modes (hence the explicit restore -- a no-op on
  # the engines that preserve it, and the difference between "closed the
  # image" and "lost my place" on the ones that don't). The end-to-end
  # outcome -- scroll position preserved across open+close on a genuinely
  # scrolled page -- is asserted in a real browser.
  "  if(target&&target.focus&&document.contains(target)){\n" &
  "    try{target.focus({preventScroll:true});}catch(e){target.focus();}\n" &
  "  }\n" &
  "  if(typeof window!=='undefined'&&window.scrollTo){window.scrollTo(savedScrollX,savedScrollY);}\n" &
  "}\n" &
  "function buildOverlay(){\n" &
  "  if(overlay){return;}\n" &
  "  overlay=document.createElement('div');\n" &
  "  overlay.className=" & jsString(imageOverlayClass) & ";\n" &
  "  overlay.setAttribute('role','dialog');\n" &
  "  overlay.setAttribute('aria-modal','true');\n" &
  "  overlay.setAttribute('aria-label',DIALOG_LABEL);\n" &
  "  overlay.setAttribute('tabindex','-1');\n" &
  "  overlay.setAttribute(OPEN,'false');\n" &
  "  overlay.hidden=true;\n" &
  "  closeBtn=document.createElement('button');\n" &
  "  closeBtn.setAttribute('type','button');\n" &
  "  closeBtn.className=" & jsString(imageOverlayCloseClass) & ";\n" &
  "  closeBtn.setAttribute('aria-label',CLOSE_LABEL);\n" &
  "  closeBtn.appendChild(document.createTextNode('\\u00d7'));\n" &
  "  overlay.appendChild(closeBtn);\n" &
  "  overlayImg=document.createElement('img');\n" &
  "  overlayImg.className=" & jsString(imageOverlayImageClass) & ";\n" &
  "  overlay.appendChild(overlayImg);\n" &
  "  overlayCaption=document.createElement('p');\n" &
  "  overlayCaption.className=" & jsString(imageOverlayCaptionClass) & ";\n" &
  "  overlay.appendChild(overlayCaption);\n" &
  "  closeBtn.addEventListener('click',function(ev){ev.preventDefault();closeViewer();});\n" &
  # Backdrop dismissal: ONLY a click on the overlay itself -- never one
  # that landed on the image, the caption or the close button.
  "  overlay.addEventListener('click',function(ev){if(ev.target===overlay){closeViewer();}});\n" &
  "  document.body.appendChild(overlay);\n" &
  "}\n" &
  "function openViewer(src,alt){\n" &
  "  buildOverlay();\n" &
  "  lastFocused=document.activeElement;\n" &
  "  savedScrollX=(typeof window!=='undefined'&&window.pageXOffset)||0;\n" &
  "  savedScrollY=(typeof window!=='undefined'&&window.pageYOffset)||0;\n" &
  "  overlayImg.setAttribute('src',src);\n" &
  "  overlayImg.setAttribute('alt',alt||'');\n" &
  "  overlay.setAttribute('aria-label',alt?(DIALOG_LABEL+': '+alt):DIALOG_LABEL);\n" &
  "  overlayCaption.textContent=alt||'';\n" &
  "  overlayCaption.hidden=!alt;\n" &
  "  overlay.hidden=false;\n" &
  "  overlay.setAttribute(OPEN,'true');\n" &
  "  try{document.documentElement.setAttribute(LOCK,'true');}catch(e){}\n" &
  "  closeBtn.focus();\n" &
  "}\n" &
  # --- opening: delegated, so soft-navigated / tab-revealed images work too
  "document.addEventListener('click',function(ev){\n" &
  "  if(ev.defaultPrevented){return;}\n" &
  "  if(ev.metaKey||ev.ctrlKey||ev.shiftKey||ev.altKey){return;}\n" &
  "  if(typeof ev.button==='number'&&ev.button!==0){return;}\n" &
  "  var t=ev.target;\n" &
  "  if(!t||!t.closest){return;}\n" &
  "  var fig=t.closest('.'+FIG);\n" &
  "  if(!fig){return;}\n" &
  # Measured as NOT downscaled (or not measured yet): the affordance is
  # hidden and the image is not a control -- leave the event alone, so the
  # no-JS link semantics still hold if anything reaches it.
  "  if(fig.getAttribute(ZOOM)!=='true'){return;}\n" &
  "  var img=figureImage(fig);\n" &
  "  if(!img){return;}\n" &
  "  if(t!==img&&!t.closest('.'+EXP)){return;}\n" &
  "  ev.preventDefault();\n" &
  "  openViewer(img.currentSrc||img.getAttribute('src')||'',img.getAttribute('alt')||'');\n" &
  "});\n" &
  # --- closing + focus trap, on the document in the CAPTURE phase so they
  # win regardless of what currently holds focus.
  "document.addEventListener('keydown',function(ev){\n" &
  "  if(!isOpen()){return;}\n" &
  "  var k=ev.key;\n" &
  "  if(k==='Escape'||k==='Esc'){ev.preventDefault();closeViewer();return;}\n" &
  # The dialog has exactly one focus stop (its close button), so trapping
  # is simply "Tab and Shift+Tab can never leave it".
  "  if(k==='Tab'){ev.preventDefault();if(closeBtn&&closeBtn.focus){closeBtn.focus();}}\n" &
  "},true);\n" &
  # --- re-measure triggers: load (does not bubble -> capture), viewport
  # resize, and any DOM change (SPA route swap, revealed tab panel).
  "document.addEventListener('load',function(ev){\n" &
  "  var t=ev.target;\n" &
  "  if(t&&t.classList&&t.classList.contains(IMG)){scheduleMeasure();}\n" &
  "},true);\n" &
  "if(typeof window!=='undefined'&&window.addEventListener){\n" &
  "  window.addEventListener('resize',scheduleMeasure);\n" &
  "  window.addEventListener('load',scheduleMeasure);\n" &
  "}\n" &
  "if(typeof MutationObserver==='function'&&document.body){\n" &
  # `data-zoomable` is deliberately absent from the attribute filter, so
  # this observer can never be re-triggered by `measure`'s own writes.
  "  try{new MutationObserver(scheduleMeasure).observe(document.body," &
       "{childList:true,subtree:true,attributes:true,attributeFilter:['hidden','src']});}catch(e){}\n" &
  "}\n" &
  "document.addEventListener('DOMContentLoaded',scheduleMeasure);\n" &
  "scheduleMeasure();\n" &
  "}catch(e){}\n" &
  "})();"

proc renderImageViewerScriptHtml*(): string =
  ## The `<script>` element the SSR path emits as the LAST thing inside
  ## `<body>` -- after the document's own markup, so the first measuring
  ## pass sees a fully parsed page (and, unlike a `<head>` script, needs
  ## no readiness dance for the initial pass).
  "<script id=\"" & imageViewerScriptId & "\">" & imageViewerScriptBody() & "</script>"

proc withImageViewerScript*(html: string): string =
  ## Splices `renderImageViewerScriptHtml()` in just before the document's
  ## closing `</body>` (there is exactly one, emitted by `ssr.renderRoute`).
  ## Idempotent: a document that already carries the viewer script is
  ## returned unchanged, so a plugin that re-runs this can't double-emit.
  if html.contains("id=\"" & imageViewerScriptId & "\""): return html
  let idx = html.rfind("</body>")
  if idx < 0: return html
  html[0 ..< idx] & renderImageViewerScriptHtml() & html[idx .. ^1]
