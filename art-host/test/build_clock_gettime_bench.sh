#!/usr/bin/env bash
# Build the clock_gettime micro-benchmark two ways IN the VM:
#   1) glibc (system gcc)              -> /tmp/cgt_glibc   (VDSO baseline)
#   2) host-musl (soong crt + libc_musl.so) -> /tmp/cgt_musl
#
# The host-musl link mirrors how soong links a host-musl PIE: relinterp-based
# startup (crtbegin_dynamic), Scrt1.o, no PT_INTERP, link against the shared
# libc_musl.so. This lets us relink the bench against a freshly-rebuilt
# libc_musl.so without rebuilding all of ART.
set -euo pipefail

AOSP=/opt/aosp/main-art
CLANG=$AOSP/prebuilts/clang/host/linux-arm64/clang-r584948b/bin/clang
HOSTLIB=$AOSP/out/host/linux-arm64/lib64
INT=$AOSP/out/soong/.intermediates/external/musl
SRC=${1:?usage: build_clock_gettime_bench.sh <path-to-clock_gettime_bench.c>}

# In the relinterp model crtbegin_dynamic provides _start/_start_c, so we do
# NOT link Scrt1.o (it would duplicate _start/_start_c).
CRTBEGIN=$INT/libc_musl_crtbegin_dynamic/linux_musl_arm64/libc_musl_crtbegin_dynamic.o
CRTEND=$INT/libc_musl_crtend/linux_musl_arm64/libc_musl_crtend.o
BUILTINS=$AOSP/prebuilts/clang/host/linux-x86/clang-r584948b/lib/clang/22/lib/linux/aarch64-unknown-linux-musl/lib/linux/libclang_rt.builtins-aarch64.a

for f in "$CRTBEGIN" "$CRTEND" "$HOSTLIB/libc_musl.so"; do
  [ -e "$f" ] || { echo "MISSING: $f" >&2; exit 1; }
done

# --- glibc baseline ---
gcc -O2 -o /tmp/cgt_glibc "$SRC"
echo "built /tmp/cgt_glibc (glibc)"

# --- host-musl ---
# Compile object only (freestanding-ish; public musl headers are not needed for
# the public clock_gettime API, so use the toolchain's musl target headers).
"$CLANG" -target aarch64-linux-musl -O2 -fPIE -c "$SRC" -o /tmp/cgt_musl.o

# Link as a PIE with NO PT_INTERP (relinterp model), against shared libc_musl.so.
"$CLANG" -target aarch64-linux-musl -fuse-ld=lld -nostdlib -pie \
  -Wl,--no-dynamic-linker \
  -o /tmp/cgt_musl \
  "$CRTBEGIN" /tmp/cgt_musl.o "$CRTEND" \
  -L"$HOSTLIB" -Wl,-rpath,"$HOSTLIB" \
  -Wl,--no-as-needed -lc_musl \
  "$BUILTINS"
echo "built /tmp/cgt_musl (host-musl)"
