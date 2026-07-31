## Live Metacraft design-system editor -- JS-target mount harness.
##
## Mirrors `isonim/src/isonim/editor/main.nim` (the editor package's own
## reference mount harness), but instead of the wanderlust travel demo it
## constructs the *Metacraft docs* workspace: the real `--docs-*` token
## layer (`site/src/theme_tokens.isonimDocsTokenLayer`) resolved against the
## canonical `codetracer-design-system` DTCG set, adapted into an
## `EditorWorkspace` by `dtcg_workspace`, then handed to `mountEditor`.
##
## The DTCG JSON is embedded at COMPILE TIME via `staticRead` because the JS
## target has no filesystem (`core/tokens.loadTokens` would raise there);
## `loadTokensFromStrings` turns the embedded documents into the resolvable
## `TokenSet` the adapter's `bkToken` bindings resolve against.

when not defined(js):
  {.error: "design/main.nim is the JS-target mount harness; compile with `nim js`".}

import isonim/core/signals
import isonim/editor
import isonim/editor/browser
import core/tokens
import ../src/theme_tokens
import ./dtcg_workspace

const
  brandJson = staticRead("../../../codetracer-design-system/brand/brand.json")
  aliasJson = staticRead("../../../codetracer-design-system/alias/alias.json")
  mappedJson = staticRead("../../../codetracer-design-system/mapped/mapped.json")

proc main() =
  let ts = loadTokensFromStrings([brandJson, aliasJson, mappedJson])
  let layer = isonimDocsTokenLayer()

  var editor: EditorVM
  var ws = metacraftEditorWorkspace(layer, ts,
    tokensAccessor = proc(): seq[FoundationTokenEntry] =
      if editor.isNil: @[] else: editor.foundations.tokens.val,
    # M4b: the editor's foundation "Save" POSTs each edit to the dev-server save
    # route (same-origin when served by `design/serve.nim`), which patches the
    # docs token file and lets `just dev-docs` hot-reload the live docs.
    foundationSave = docsFetchPersist())

  # VBIND-M7 LOAD: the save server embeds `design/.isonim/bindings.json` as
  # `window.__ISONIM_BINDINGS__` ahead of this bundle. Seed the workspace's
  # binding metadata from it BEFORE mounting, so `applyWorkspace` rehydrates the
  # linked chips + previously-linked history. Absent/malformed ⇒ empty (no-op).
  ws.loadBindingSidecar(readInjectedBindingsSidecar())

  editor = mountEditor(ws)

  # VBIND-M7 SAVE: on every bind/detach, snapshot the live binding metadata and
  # POST the serialized sidecar to the dev-server bindings route, which writes
  # `design/.isonim/bindings.json`. This NEVER touches the DTCG token source.
  editor.inspector.onBindingsChanged = proc() {.closure.} =
    let meta = editor.collectWorkspaceBindingMetadata()
    postDocsBindingsSave(docsBindingsEndpoint,
      bindingSidecarJson(meta.bindings, meta.history))

main()
