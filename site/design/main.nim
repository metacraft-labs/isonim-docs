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
  let ws = metacraftEditorWorkspace(layer, ts,
    tokensAccessor = proc(): seq[FoundationTokenEntry] =
      if editor.isNil: @[] else: editor.foundations.tokens.val)
  editor = mountEditor(ws)

main()
