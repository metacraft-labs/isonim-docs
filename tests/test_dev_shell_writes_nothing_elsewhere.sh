#!/usr/bin/env bash
# Entering this repository's dev shell writes nothing into the git checkout it
# is entered from: not into another repository, and not into this one.
#
# The shell reuses isonim's dev shell through `inputsFrom`, which also runs
# isonim's shellHook. That hook installs isonim's git hooks
# (`.pre-commit-config.yaml`, `.git/hooks`, `core.hooksPath`) into
# `git rev-parse --show-toplevel` of the current directory, so it planted
# isonim's hooks into whatever checkout `nix develop` ran in -- this repository
# included. flake.nix takes isonim's toolchain without its shellHook.
#
# Like `.envrc`, the `isonim` input is pointed at the sibling `../isonim`
# checkout when there is one (set ISONIM_DOCS_ISONIM_INPUT to choose another
# flake reference, or to "pinned" to use flake.lock's pin).
#
# Asserted, from a scratch git repository, a subdirectory of it, and this
# repository: no file or directory appears, no hook is installed and
# `core.hooksPath` is untouched.
#
#   bash tests/test_dev_shell_writes_nothing_elsewhere.sh
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

isonim_input="${ISONIM_DOCS_ISONIM_INPUT:-}"
if [ -z "$isonim_input" ] && [ -f "$REPO/../isonim/flake.nix" ]; then
  isonim_input="path:$(cd "$REPO/../isonim" && pwd)"
fi
override=()
if [ -n "$isonim_input" ] && [ "$isonim_input" != pinned ]; then
  override=(--override-input isonim "$isonim_input")
fi

enter() {
  ( cd "$1" && nix develop "$REPO" --no-write-lock-file "${override[@]}" -c true ) >/dev/null 2>&1 \
    || fail "the dev shell did not start from $1"
}

git -C "$SCRATCH" init -q
git -C "$SCRATCH" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$SCRATCH/sub"
hooks_before="$(ls "$SCRATCH/.git/hooks")"

for dir in "$SCRATCH" "$SCRATCH/sub"; do
  enter "$dir"
  [ -z "$(git -C "$SCRATCH" status --porcelain --ignored)" ] \
    || fail "entered from $dir: files were written into the other repository: $(git -C "$SCRATCH" status --porcelain --ignored | tr '\n' ' ')"
  # git status does not list empty directories.
  extra="$(cd "$SCRATCH" && find . -mindepth 1 -path ./.git -prune -o ! -path ./sub -print)"
  [ -z "$extra" ] || fail "entered from $dir: entries were created in the other repository: $(echo $extra)"
  [ "$(ls "$SCRATCH/.git/hooks")" = "$hooks_before" ] \
    || fail "entered from $dir: git hooks were installed into the other repository"
  [ -z "$(git -C "$SCRATCH" config --local --get core.hooksPath || true)" ] \
    || fail "entered from $dir: the other repository's core.hooksPath was changed"
done

# From this repository: isonim's hook config must not land here either.
cfg="$REPO/.pre-commit-config.yaml"
if [ -L "$cfg" ]; then rm -f "$cfg"; fi
enter "$REPO"
[ ! -e "$cfg" ] && [ ! -L "$cfg" ] \
  || fail "entered from this repository, isonim's .pre-commit-config.yaml was installed here: $(readlink "$cfg")"

echo "PASS: the dev shell writes no hooks into the checkout it is entered from"
