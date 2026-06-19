#!/usr/bin/env bash
# In-VM: build ART host binaries for linux_musl-arm64. The C++ musl-ism
# whack-a-mole happens here; rerun after each fix.
set -euo pipefail

AOSP=/opt/aosp/main-art
cd "$AOSP"

export ALLOW_MISSING_DEPENDENCIES=true
export SOONG_ALLOW_MISSING_DEPENDENCIES=true
export USE_HOST_MUSL=true
export LLVM_PREBUILTS_VERSION=clang-r584948b
CLANG_DIR=prebuilts/clang/host/linux-arm64/$LLVM_PREBUILTS_VERSION
export LLVM_RELEASE_VERSION
LLVM_RELEASE_VERSION=$(head -1 "$CLANG_DIR/AndroidVersion.txt" | cut -d. -f1)

set +u
source build/envsetup.sh
lunch "${PRODUCT:-armv8-trunk_staging-eng}"
set -u

# --soong-only: rust prebuilt rlib variants collide in Kati's make-module
# export (upstream builds musl targets soong-only for the same reason), and
# our goals are pure Soong host modules anyway.
H=out/host/linux-arm64
DEFAULT_TARGETS="
  $H/bin/dalvikvm64
  $H/bin/dex2oat64
  $H/lib64/libart.so
  $H/lib64/libopenjdk.so
  $H/lib64/libjavacore.so
  $H/lib64/libopenjdkjvm.so
  $H/lib64/libicu_jni.so
  $H/lib64/libjavacrypto.so
  $H/lib64/libandroidio.so
  $H/com.android.i18n/etc/icu/icudt76l.dat
  $H/framework/core-oj-hostdex.jar
  $H/framework/core-libart-hostdex.jar
  $H/framework/core-icu4j-hostdex.jar
  $H/framework/okhttp-hostdex.jar
  $H/framework/bouncycastle-hostdex.jar
  $H/framework/apache-xml-hostdex.jar
  $H/framework/conscrypt-hostdex.jar
  $H/framework/d8.jar
"
# shellcheck disable=SC2086 — TARGETS is a space-separated goal list
m --soong-only ${TARGETS:-$DEFAULT_TARGETS}
echo "=== host out:"
ls -la out/host/linux-arm64/bin/ 2>/dev/null | head -20 || ls out/host/ 2>/dev/null
echo "50-build-art: OK"
