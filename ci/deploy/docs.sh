#!/usr/bin/env bash

set -e

# Build the isonim-docs self-documentation site (site/) and publish it to the
# `gh-pages` branch that GitHub Pages serves at
# https://metacraft-labs.github.io/isonim-docs/.
#
# site/ is an isonim-docs SSG consumer: `just build` runs `nim c -r src/build.nim`
# under the isonim dev shell and emits the static site into site/public/. Its
# DocsConfig sets basePath="/isonim-docs" so every internal URL is prefixed for
# the project-Pages subpath (see src/core/base_path.nim). The Metacraft brand
# DTCG tokens are read from the codetracer-design-system sibling at build time.
#
# Publish uses a throwaway git repo + force-push (NOT `git worktree --orphan`,
# which needs git 2.42+; the CI runner's git is older), so no gh-pages history is
# kept. In CI the deploy step provides DEPLOY_TOKEN (the workflow GITHUB_TOKEN)
# and GITHUB_REPOSITORY (owner/repo). Set DOCS_DEPLOY_DRY_RUN=1 (or --dry-run) to
# build + stage without pushing (neither var is needed then).

DRY_RUN=0
if [ "${DOCS_DEPLOY_DRY_RUN:-0}" = "1" ] || [ "${1:-}" = "--dry-run" ]; then
	DRY_RUN=1
fi

# --- Build the isonim-docs SSG self-docs -----------------------------------
pushd site/
nix develop ../../isonim -c just build # build output is in ./public
popd

SITE_DIR="site/public"

# --- Publish to gh-pages via a throwaway repo (force-push) -----------------
PUBLISH="$(mktemp -d)"
cp -a "$SITE_DIR/." "$PUBLISH/"
# Serve the SSG output verbatim (no Jekyll). No CNAME -- project-Pages subpath
# (basePath handles URL prefixing); add a CNAME + drop basePath for a domain.
touch "$PUBLISH/.nojekyll"

cd "$PUBLISH"
git init -q
git config user.name "Deploy from CI"
git config user.email "deploy@ci"
git add -A
git commit -q -m 'deploy isonim-docs self-docs' --no-gpg-sign

if [ "$DRY_RUN" = "1" ]; then
	echo "docs.sh: DRY RUN -- skipping push; staged $(git ls-files | wc -l) files"
else
	: "${DEPLOY_TOKEN:?DEPLOY_TOKEN required for the gh-pages push}"
	: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required (owner/repo)}"
	git push --force \
		"https://x-access-token:${DEPLOY_TOKEN}@github.com/${GITHUB_REPOSITORY}" \
		HEAD:gh-pages
fi
