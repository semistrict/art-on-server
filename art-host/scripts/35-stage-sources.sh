#!/usr/bin/env bash
# In-VM: stage the fork into the synced AOSP build tree.
#
# This repo vendors the FULL SOURCE of the eight forked projects (see the git
# history: each project is imported at its AOSP base commit, then every upstream
# patch is its own commit). We rsync that source over the freshly-synced tree so
# the build uses the fork's source directly -- there is no patch application for
# these projects anymore.
#
# Two projects are NOT vendored because their size is dominated by non-source
# data and committing them for a few changed files is impractical:
#   external/icu   (~430 MB, mostly ICU locale data) -- 3 changed files
#   prebuilts/rust (~13 GB prebuilt toolchain)       -- 1 changed file
# They remain as patches under art-host/patches/ and are applied idempotently.
set -euo pipefail

AOSP=/opt/aosp/main-art
REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"   # .../art-host
SRC="$(cd "$REPO/.." && pwd)"                        # repo root: vendored project dirs live here

VENDORED="art libcore bionic external/conscrypt build/make build/soong external/musl libnativehelper"
for p in $VENDORED; do
  [ -d "$SRC/$p" ] || { echo "missing vendored source: $SRC/$p" >&2; exit 1; }
  echo "staging vendored source -> $p"
  rsync -a --delete --exclude='.git' "$SRC/$p/" "$AOSP/$p/"
done

# Large projects kept as patches (idempotent: reverse-check skips already-applied).
shopt -s nullglob
for projdir in "$REPO"/patches/*/; do
  proj=$(basename "$projdir" | sed 's|__|/|g')
  for pch in "$projdir"/*.patch; do
    name=$(basename "$pch")
    if git -C "$AOSP/$proj" apply --reverse --check "$pch" 2>/dev/null; then
      echo "OK (already applied): $proj $name"
    elif git -C "$AOSP/$proj" apply --check "$pch" 2>/dev/null; then
      git -C "$AOSP/$proj" apply "$pch"; echo "APPLIED: $proj $name"
    else
      echo "FAILED to apply: $proj $name" >&2; exit 1
    fi
  done
done

# The static dalvikvm module lists art/dalvikvm/static_jni_symbols.cpp as a
# source; it is generated (not vendored), and the rsync --delete above removes
# any stale copy. Regenerate it now -- a stub if the static archives aren't built
# yet -- so Soong analysis sees the file on the very first `m` (otherwise the
# dalvikvms module is cached as missing-deps and 57-build-static fails). The
# two-pass in 57-build-static later refreshes it with the real symbol table.
bash "$(dirname "$0")/56-gen-static-jni-symbols.sh"

echo "35-stage-sources: OK"
