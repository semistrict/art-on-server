#!/usr/bin/env bash
# In-VM: inventory what the synced main-art tree already supports for
# arm64-host builds. Read-only; prints a report.
set -euo pipefail

AOSP=/opt/aosp/main-art
cd "$AOSP"

echo "=== prebuilt toolchain architectures present:"
ls prebuilts/clang/host/ 2>/dev/null
ls prebuilts/go/ 2>/dev/null
ls prebuilts/build-tools/ 2>/dev/null
ls prebuilts/build-tools/sysroots/ 2>/dev/null || true
ls prebuilts/jdk/*/ 2>/dev/null | head -5 || true

echo "=== Soong host arch support (arch.go osArchTypeMap / cc configs):"
grep -n "Arm64" build/soong/android/arch.go | head -20 || true
ls build/soong/cc/config/ | grep -iE "arm64|musl|linux" || true

echo "=== linux_musl / linux_bionic host-cross mentions:"
grep -rn "linux_musl" build/soong/android/arch.go | head -10 || true
grep -n "HostCross" build/soong/android/arch.go | head -10 || true

echo "=== ART static defaults + bionic host script:"
grep -rn "art_static_defaults\|static_executable" art/dex2oat/Android.bp art/runtime/Android.bp 2>/dev/null | head -10 || true
ls art/tools/ | grep -iE "bionic|host" || true

echo "=== musl sysroot prebuilts:"
find prebuilts -maxdepth 3 -iname "*musl*" 2>/dev/null | head -10 || true

echo "20-inventory: done"
