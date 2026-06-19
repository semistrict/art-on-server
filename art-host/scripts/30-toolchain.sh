#!/usr/bin/env bash
# In-VM: provision the native arm64 toolchain pieces the public master-art
# manifest lacks. Idempotent.
#   - clang: first-party prebuilts (platform/prebuilts/clang/host/linux-arm64,
#     branch mirror-goog-llvm-r596125-release ships clang-r584948b)
#   - go:    golang.org tarball matching the x86 prebuilt version
#   - jdk:   Debian openjdk-21 symlinked to prebuilts/jdk/jdk21/linux-arm64
#   - the 8 go-based build-tools missing from prebuilts/build-tools/linux-arm64
set -euo pipefail

AOSP=/opt/aosp/main-art
cd "$AOSP"

echo "--- clang (first-party arm64 prebuilts via local manifest)"
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/arm64-host.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project path="prebuilts/clang/host/linux-arm64"
           name="platform/prebuilts/clang/host/linux-arm64"
           revision="mirror-goog-llvm-r596125-release"
           clone-depth="1" />
  <!-- host musl libc reuses bionic's kernel UAPI header modules -->
  <project path="bionic" name="platform/bionic" revision="main" />
  <!-- host ICU (libicuuc/libicui18n + later core-icu4j for the SDK) -->
  <project path="external/icu" name="platform/external/icu" revision="main" />
  <!-- dex2oat links libcap -->
  <project path="external/libcap" name="platform/external/libcap" revision="main" />
  <!-- libjavacrypto.so (conscrypt JNI) for the host runtime; the module-sdk
       prebuilt only provides the dex jar -->
  <project path="external/conscrypt" name="platform/external/conscrypt" revision="main" />
</manifest>
EOF
if [ ! -d prebuilts/clang/host/linux-arm64/clang-r584948b ]; then
  repo sync -c -j4 --no-tags prebuilts/clang/host/linux-arm64 </dev/null
fi
if [ ! -d bionic/libc ]; then
  repo sync -c -j4 --no-tags bionic </dev/null
fi
if [ ! -d external/icu/icu4c ]; then
  repo sync -c -j4 --no-tags external/icu </dev/null
fi
if [ ! -d external/libcap/libcap ] && [ ! -f external/libcap/Android.bp ]; then
  repo sync -c -j4 --no-tags external/libcap </dev/null
fi
if [ ! -f external/conscrypt/Android.bp ]; then
  repo sync -c -j4 --no-tags external/conscrypt </dev/null
fi

echo "--- rust toolchain (dist tarballs, musl-hosted, pinned version)"
# the musl-hosted rustc needs the musl dynamic loader on the build machine
[ -e /lib/ld-musl-aarch64.so.1 ] || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq musl
RUSTVER=$(grep -oE 'RustDefaultVersion = "[0-9.]+"' build/soong/rust/config/global.go | grep -oE '[0-9.]+')
# NOTE dir name: soong's rust HostPrebuiltTag uses linux-musl-arm64 for musl
# hosts (see patches/build__soong)
if [ -d "prebuilts/rust/linux-arm64/$RUSTVER" ] && [ ! -d "prebuilts/rust/linux-musl-arm64/$RUSTVER" ]; then
  mkdir -p prebuilts/rust/linux-musl-arm64
  mv "prebuilts/rust/linux-arm64/$RUSTVER" "prebuilts/rust/linux-musl-arm64/$RUSTVER"
  rmdir prebuilts/rust/linux-arm64 2>/dev/null || true
fi
# The toolchain must be MUSL-HOSTED (like Android's own rust prebuilts):
# Soong builds proc-macro dylibs for the musl host triple and rustc must be
# able to dlopen them. aarch64-unknown-linux-musl is tier-2 *with host
# tools*, and its static-musl binaries run fine on the glibc build VM.
if [ -d "prebuilts/rust/linux-musl-arm64/$RUSTVER" ] \
   && [ ! -f "prebuilts/rust/linux-musl-arm64/$RUSTVER/.musl-host" ]; then
  rm -rf "prebuilts/rust/linux-musl-arm64/$RUSTVER"
fi
if [ ! -x "prebuilts/rust/linux-musl-arm64/$RUSTVER/bin/rustc" ]; then
  # rustup refuses cross-host toolchains; use the dist tarballs directly
  # (each ships an install.sh).
  T=aarch64-unknown-linux-musl
  DEST="$AOSP/prebuilts/rust/linux-musl-arm64/$RUSTVER"
  rm -rf "$DEST" /tmp/rust-dist
  mkdir -p "$DEST" /tmp/rust-dist
  for comp in "rust-$RUSTVER-$T" "clippy-$RUSTVER-$T" "rust-src-$RUSTVER"; do
    echo "fetching $comp"
    curl -fL --retry 3 -o "/tmp/rust-dist/$comp.tar.xz" \
      "https://static.rust-lang.org/dist/$comp.tar.xz"
    tar -xJf "/tmp/rust-dist/$comp.tar.xz" -C /tmp/rust-dist
    "/tmp/rust-dist/$comp/install.sh" --prefix="$DEST" --disable-ldconfig >/dev/null
  done
  rm -rf /tmp/rust-dist
  touch "$DEST/.musl-host"
fi
# the musl-hosted rustc unwinds via a musl-built libgcc_s; Debian has no musl
# libgcc, so take Alpine's (lands in the toolchain lib dir, which is on the
# binaries' $ORIGIN rpath)
RUSTLIB="prebuilts/rust/linux-musl-arm64/$RUSTVER/lib"
if [ ! -e "$RUSTLIB/libgcc_s.so.1" ]; then
  apk=$(curl -fsSL https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/aarch64/ \
        | grep -oE 'libgcc-[0-9][^"]*\.apk' | head -1)
  [ -n "$apk" ] || { echo "cannot find Alpine libgcc apk" >&2; exit 1; }
  curl -fsSL -o /tmp/libgcc.apk "https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/aarch64/$apk"
  tar -xzf /tmp/libgcc.apk -C /tmp usr/lib/libgcc_s.so.1 2>/dev/null || true
  cp /tmp/usr/lib/libgcc_s.so.1 "$RUSTLIB/"
  rm -rf /tmp/libgcc.apk /tmp/usr
fi
ls -la "$RUSTLIB/libgcc_s.so.1"
# rust's vendored compiler-builtins ships multc3.o (complex-f128 multiply)
# whose clang build leaves an undefined __builtin_copysignq on aarch64-musl;
# it gets force-included via whole-archive into every rust staticlib. Nothing
# uses __multc3 — drop the member. (If something ever does, the undefined
# symbol will name it explicitly.)
AR="$AOSP/prebuilts/clang/host/linux-arm64/clang-r584948b/bin/llvm-ar"
for rlib in "$AOSP/prebuilts/rust/linux-musl-arm64/$RUSTVER/lib/rustlib/aarch64-unknown-linux-musl/lib/"libcompiler_builtins-*.rlib; do
  members=$("$AR" t "$rlib" | grep -E "multc3" || true)
  if [ -n "$members" ]; then
    # shellcheck disable=SC2086
    "$AR" d "$rlib" $members
    echo "removed from $(basename "$rlib"): $members"
  fi
done
# Android's rust build rules pass nightly-only -Z flags; Android's own rustc
# prebuilts are built to accept them, rustup's stable refuses. RUSTC_BOOTSTRAP
# unlocks -Z on stable — wrap the binaries so it is always set.
for tool in rustc clippy-driver; do
  T="prebuilts/rust/linux-musl-arm64/$RUSTVER/bin/$tool"
  if [ -x "$T" ] && [ ! -x "$T.real" ] && file "$T" | grep -q ELF; then
    mv "$T" "$T.real"
  fi
  if [ -x "$T.real" ]; then
    # absolute path: build actions run with PWD=/proc/self/cwd games that
    # break relative dirname resolution
    printf '#!/bin/sh\nexport RUSTC_BOOTSTRAP=1\nexec "%s/%s.real" "$@"\n' \
      "$AOSP/prebuilts/rust/linux-musl-arm64/$RUSTVER/bin" "$tool" > "$T"
    chmod +x "$T"
  fi
done
"prebuilts/rust/linux-musl-arm64/$RUSTVER/bin/rustc" --version
"prebuilts/rust/linux-musl-arm64/$RUSTVER/bin/clippy-driver" --version
# ensure linux-x86 is back at the manifest-pinned revision (an earlier
# experiment re-pinned it to the mirror branch, whose soong plugin is
# incompatible with master-art's soong)
if [ -d prebuilts/clang/host/linux-x86/soong ] && grep -q "config.ClangVersion" prebuilts/clang/host/linux-x86/soong/clangprebuilts.go 2>/dev/null; then
  repo sync -c -j4 --no-tags --force-sync --detach prebuilts/clang/host/linux-x86 </dev/null
fi
# Graft the clang-r584948b runtime archives (libclang_rt for every target and
# host-musl triple) into the linux-x86 repo: its Android.bp/soong plugin
# declares the libclang_rt prebuilt modules with paths under its own tree,
# templated by LLVM_PREBUILTS_VERSION. Compiler binaries still come from the
# linux-arm64 repo (Soong resolves ${ClangBase}/${HostPrebuiltTag}).
if [ ! -d prebuilts/clang/host/linux-x86/clang-r584948b/lib ]; then
  mkdir -p prebuilts/clang/host/linux-x86/clang-r584948b
  cp -a prebuilts/clang/host/linux-arm64/clang-r584948b/lib \
        prebuilts/clang/host/linux-x86/clang-r584948b/
  cp -a prebuilts/clang/host/linux-arm64/clang-r584948b/AndroidVersion.txt \
        prebuilts/clang/host/linux-x86/clang-r584948b/ 2>/dev/null || true
  # bp globs may reference these too; cheap to provide
  for d in share include runtimes_ndk_cxx android_libc++; do
    [ -d "prebuilts/clang/host/linux-arm64/clang-r584948b/$d" ] \
      && cp -a "prebuilts/clang/host/linux-arm64/clang-r584948b/$d" \
               "prebuilts/clang/host/linux-x86/clang-r584948b/" || true
  done
fi
ls prebuilts/clang/host/linux-arm64/ | head -4
ls prebuilts/clang/host/linux-x86/ | grep clang- | head -6

echo "--- go (golang.org, version-matched to the x86 prebuilt)"
GOVER=$(head -1 prebuilts/go/linux-x86/VERSION)
if [ ! -x prebuilts/go/linux-arm64/bin/go ]; then
  curl -fL --retry 3 -o /tmp/go.tgz "https://go.dev/dl/${GOVER}.linux-arm64.tar.gz"
  rm -rf prebuilts/go/linux-arm64 /tmp/go-extract
  mkdir -p /tmp/go-extract
  tar -xzf /tmp/go.tgz -C /tmp/go-extract
  mv /tmp/go-extract/go prebuilts/go/linux-arm64
  rm -rf /tmp/go.tgz /tmp/go-extract
fi
prebuilts/go/linux-arm64/bin/go version
# microfactory invokes the raw `compile` tool, which needs precompiled stdlib
# export data in GOROOT/pkg/linux_arm64 (AOSP's go prebuilts ship it;
# golang.org tarballs stopped). Install it in place.
if [ ! -f prebuilts/go/linux-arm64/pkg/linux_arm64/bytes.a ]; then
  GOROOT="$AOSP/prebuilts/go/linux-arm64" GODEBUG=installgoroot=all \
    GOFLAGS= GOPATH=/tmp/gopath-stdinstall \
    prebuilts/go/linux-arm64/bin/go install std
fi
ls prebuilts/go/linux-arm64/pkg/linux_arm64/bytes.a

echo "--- jdk21 (Debian openjdk-21, copied — kati \$(shell find) does not follow symlinks)"
command -v javac >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-21-jdk-headless
JVM=/usr/lib/jvm/java-21-openjdk-arm64
[ -d "$JVM" ] || { echo "JDK not found at $JVM" >&2; exit 1; }
if [ -L prebuilts/jdk/jdk21/linux-arm64 ]; then rm prebuilts/jdk/jdk21/linux-arm64; fi
if [ ! -x prebuilts/jdk/jdk21/linux-arm64/bin/javac ]; then
  rsync -a --delete --copy-links "$JVM/" prebuilts/jdk/jdk21/linux-arm64/
fi
prebuilts/jdk/jdk21/linux-arm64/bin/javac --version

echo "--- jdk8 bootclasspath jars (arch-independent; java_version<9 modules reference them under the host tag)"
if [ ! -e prebuilts/jdk/jdk8/linux-arm64/jre/lib/rt.jar ]; then
  mkdir -p prebuilts/jdk/jdk8/linux-arm64/jre
  rsync -a prebuilts/jdk/jdk8/linux-x86/jre/lib prebuilts/jdk/jdk8/linux-arm64/jre/
fi
ls prebuilts/jdk/jdk8/linux-arm64/jre/lib/rt.jar

echo "--- missing native go build-tools"
export GOROOT="$AOSP/prebuilts/go/linux-arm64"
export PATH="$GOROOT/bin:$PATH"
BT="$AOSP/prebuilts/build-tools/linux-arm64/bin"
build_tool() { # <output-name> <package-dir>
  local out="$1" pkgdir="$2"
  [ -x "$BT/$out" ] && { echo "have $out"; return 0; }
  echo "building $out from $pkgdir"
  (cd "$pkgdir" && GOPROXY=off go build -o "$BT/$out" .)
}
build_tool soong_zip  build/soong/zip/cmd
build_tool zip2zip    build/soong/cmd/zip2zip
build_tool merge_zips build/soong/cmd/merge_zips
build_tool bpfmt      build/blueprint/bpfmt

echo "30-toolchain: OK"
