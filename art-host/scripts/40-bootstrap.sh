#!/usr/bin/env bash
# In-VM: first build-system bootstrap on the arm64 host.
# Milestone: soong_ui builds via microfactory (arm64 go), lunch succeeds,
# `m nothing` completes (soong analysis + kati + ninja no-op).
set -euo pipefail

AOSP=/opt/aosp/main-art
cd "$AOSP"

# host = linux_musl-arm64: the only fully-wired arm64 host cc toolchain in
# Soong (registered in cc/config/arm_linux_host.go; libc_musl built in-tree).
# On linux/arm64 Soong's determineBuildOS forces LinuxMusl anyway; the env
# var also covers the make-side (binary.mk) checks.
export USE_HOST_MUSL=true
# the arm64 clang prebuilt ships a newer rev than the pinned default; the
# release version (clang major) must match the prebuilt's AndroidVersion.txt
# or the clang_rt builtins paths won't resolve.
export LLVM_PREBUILTS_VERSION=clang-r584948b
CLANG_DIR=prebuilts/clang/host/linux-arm64/$LLVM_PREBUILTS_VERSION
if [ -f "$CLANG_DIR/AndroidVersion.txt" ]; then
  export LLVM_RELEASE_VERSION
  LLVM_RELEASE_VERSION=$(head -1 "$CLANG_DIR/AndroidVersion.txt" | cut -d. -f1)
  echo "clang: $LLVM_PREBUILTS_VERSION (release $LLVM_RELEASE_VERSION)"
fi

# the master-art manifest is a subset of AOSP main; missing-module errors are
# expected and tolerated (same setting ART's own buildbot uses)
export ALLOW_MISSING_DEPENDENCIES=true
export SOONG_ALLOW_MISSING_DEPENDENCIES=true

set +u  # envsetup.sh is not set -u clean
source build/envsetup.sh
PRODUCT="${PRODUCT:-armv8-trunk_staging-eng}"
if ! lunch "$PRODUCT"; then
  echo "=== lunch $PRODUCT failed; available products:"
  grep -rhE "^[A-Za-z0-9_.-]+-(trunk|aosp)" build/make/target/product/AndroidProducts.mk 2>/dev/null || true
  find . -maxdepth 3 -name AndroidProducts.mk | head
  exit 1
fi
set -u

m nothing
echo "40-bootstrap: OK"
