#!/usr/bin/env bash
# In-VM: apply the fork's patch series to the synced tree. Idempotent:
# already-applied patches are detected via reverse-check and skipped.
# Patch layout: patches/<project path with __ for />/NNNN-*.patch
set -euo pipefail

AOSP=/opt/aosp/main-art
REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"

shopt -s nullglob
for projdir in "$REPO"/patches/*/; do
  proj=$(basename "$projdir" | sed 's|__|/|g')
  for p in "$projdir"/*.patch; do
    name=$(basename "$p")
    if git -C "$AOSP/$proj" apply --reverse --check "$p" 2>/dev/null; then
      echo "OK (already applied): $proj $name"
    elif git -C "$AOSP/$proj" apply --check "$p" 2>/dev/null; then
      git -C "$AOSP/$proj" apply "$p"
      echo "APPLIED: $proj $name"
    else
      echo "FAILED to apply: $proj $name" >&2
      git -C "$AOSP/$proj" apply --check "$p" || true
      exit 1
    fi
  done
done
echo "35-apply-patches: OK"
