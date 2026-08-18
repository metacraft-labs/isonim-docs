## The Metacraft docs token layer now ships FROM the design system -- this file
## is a thin re-export so this site's `build.nim`/`dev.nim` keep importing
## `./theme_tokens` unchanged. (This site's OWN identity -- title/footer, no
## logo -- is chrome set in `docs_config.nim`; the token VALUES are the shared,
## product-neutral docs palette.) Edit the tokens in
## `codetracer-design-system/docs/codetracer-docs.tokens.json` (or via the live
## design-system editor), never here.
import metacraft_docs_theme
export metacraft_docs_theme
