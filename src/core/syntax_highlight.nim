## isonim-docs `core/syntax_highlight` -- kept for compatibility: the
## build-time tokenizer moved to IsoNim itself, as
## `isonim/content/highlight`, where its languages became a registry.
##
## This module re-exports that module, so `tokenize(lang, code)`,
## `Token` and `TokenKind` are unchanged (and the registry API --
## `LanguageRegistry`, `builtinLanguages`, `registerLanguage` -- is
## reachable from here too). New code should import
## `isonim/content/highlight`.

{.deprecated: "isonim-docs' core/syntax_highlight moved to IsoNim: import isonim/content/highlight instead".}

import isonim/content/highlight as contentHighlight
export contentHighlight
