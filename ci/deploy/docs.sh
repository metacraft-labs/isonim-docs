#!/usr/bin/env bash

set -e

# Build the isonim-docs self-documentation site (site/) and publish it to the
# `gh-pages` orphan branch that GitHub Pages serves at
# https://metacraft-labs.github.io/isonim-docs/.
#
# site/ is an isonim-docs SSG consumer: `just build` runs
# `nim c -r src/build.nim` under the isonim dev shell and emits the static site
# (17 pages + hashed stylesheet + search index + sitemap.xml + robots.txt) into
# site/public/. Its DocsConfig sets basePath="/isonim-docs" so every internal
# URL is prefixed for the project-Pages subpath (see src/core/base_path.nim).
#
# Set DOCS_DEPLOY_DRY_RUN=1 (or pass --dry-run) to build + stage the gh-pages
# content WITHOUT committing or pushing (CI build-only verification uses this so
# the real deploy is never exercised outside a `main` run).

DRY_RUN=0
if [ "${DOCS_DEPLOY_DRY_RUN:-0}" = "1" ] || [ "${1:-}" = "--dry-run" ]; then
	DRY_RUN=1
fi

# --- Build the isonim-docs SSG self-docs -----------------------------------
# The consumer switches `--path` to sibling checkouts (isonim, nim-everywhere,
# nim-faststreams, nim-stew, and isonim's vendored deps) laid out one level
# above this repo, and its toolchain comes from the isonim flake's dev shell.
# From site/, the sibling isonim flake is at ../../isonim.
pushd site/
nix develop ../../isonim -c just build # build output is in ./public
popd

# --- Publish site/public/ to the gh-pages orphan branch --------------------

git worktree prune
if [ -d "gh-pages" ]; then
	git worktree remove --force gh-pages
fi
if git show-ref --verify --quiet refs/heads/gh-pages; then
	git branch -D gh-pages
fi

# Orphan branch (no history kept -- cheap) overwriting any existing gh-pages.
git worktree add --orphan -B gh-pages gh-pages
cp -a site/public/. gh-pages

# Serve the SSG output verbatim: disable Jekyll so files/dirs are published
# untouched. No CNAME -- this is a GitHub *project* Pages site served under the
# /isonim-docs subpath (basePath handles the URL prefixing). Add a CNAME here
# and drop basePath/adjust baseUrl once a custom domain is DNS-ready.
touch gh-pages/.nojekyll

git config user.name "Deploy from CI"
git config user.email ""
cd gh-pages
git add -A
git commit -m 'deploy isonim-docs self-docs' --no-gpg-sign

if [ "$DRY_RUN" = "1" ]; then
	echo "docs.sh: DRY RUN -- skipping 'git push origin +gh-pages'"
	echo "docs.sh: staged $(git ls-files | wc -l) files for gh-pages"
else
	git push origin +gh-pages
fi
cd ..

git worktree remove --force gh-pages
if git show-ref --verify --quiet refs/heads/gh-pages; then
	git branch -D gh-pages
fi
