# isonim-docs/site/design -- the live design-system editor harness.
#
# The parent `site/config.nims` already wires the isonim-docs framework
# (`core/tokens`, `core/docs_tokens`), the isonim framework src, and the
# vendored chronicles/faststreams/stew deps. This harness ADDITIONALLY
# mounts the isonim EDITOR package (`isonim/editor`, `isonim/editor/browser`),
# whose view-model + streaming-preview import chain needs the same extra
# sibling-repo paths and defines that isonim's own `tests/config.nims`
# sets up. This file supplies only that delta (the parent config still
# applies -- Nim stacks every config.nims from the workspace root down to
# the project dir).
import std/os

let root = currentSourcePath().parentDir()          ## .../isonim-docs/site/design
let siblingRoot = root / "../../.."                 ## .../codetracer-ci-refactor/

# --- editor streaming-preview import chain ---------------------------------
switch("path", siblingRoot / "isonim-render-serve/src")
switch("path", siblingRoot / "nim-acp/src")
switch("path", siblingRoot / "nim-agent-harbor/src")
switch("path", siblingRoot / "nim-agents/src")
switch("path", siblingRoot / "isonim/vendor/db_connector/src")

# --- object-variant semantics the editor VM relies on ----------------------
# (isonim/tests/config.nims sets this for the same editor import chain;
#  without it streaming_preview.nim fails with "only a 'ref object' can be
#  raised" and its case-object accessors go undeclared.)
switch("define", "nimOldCaseObjects")
