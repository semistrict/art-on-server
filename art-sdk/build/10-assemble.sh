#!/usr/bin/env bash
# In-VM: assemble the distributable ART SDK from the host build artifacts in
# /opt/aosp/main-art into a relocatable staging tree, then emit a .tar.zst.
# Idempotent. The SDK repo (this checkout) provides bin/art, libexec/*, the
# examples and tests; everything else comes from the build.
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
AOSP=/opt/aosp/main-art
H=$AOSP/out/host/linux-arm64
I=$AOSP/out/soong/.intermediates
STRIP=$AOSP/prebuilts/clang/host/linux-arm64/clang-r584948b/bin/llvm-strip
MINIHUB_TOOLS=/opt/minihub/tools

VERSION=$(cat "$REPO/sdk/VERSION")
ARCH=arm64
NAME="artsdk-$VERSION-linux-$ARCH"
DIST="${DIST:-/opt/art-sdk-dist}"
STAGE="$DIST/$NAME"

rm -rf "$STAGE"
mkdir -p "$STAGE"/{bin,libexec,lib/bootjars,lib/compile,lib/tools,lib/i18n/etc/icu,lib/tzdata,lib/android/etc/security,lib/boot,share,tests,docs}

echo "== binaries (static, stripped)"
cp "$H/bin/dalvikvms" "$STAGE/bin/dalvikvm"
cp "$H/bin/dex2oats" "$STAGE/bin/dex2oat"
"$STRIP" "$STAGE/bin/dalvikvm" "$STAGE/bin/dex2oat"

echo "== driver, helpers, wrappers"
cp "$REPO/sdk/bin/art" "$STAGE/bin/art"
cp "$REPO/sdk/libexec/"* "$STAGE/libexec/"
cat > "$STAGE/bin/d8" <<'EOF'
#!/usr/bin/env bash
exec "$(cd "$(dirname "$0")" && pwd)/art" d8 "$@"
EOF
cat > "$STAGE/bin/javac-art" <<'EOF'
#!/usr/bin/env bash
exec "$(cd "$(dirname "$0")" && pwd)/art" compile "$@"
EOF
chmod +x "$STAGE"/bin/* "$STAGE"/libexec/*

echo "== bootclasspath jars (dex)"
for j in core-oj core-libart core-icu4j okhttp bouncycastle apache-xml conscrypt; do
  cp "$H/framework/$j-hostdex.jar" "$STAGE/lib/bootjars/$j-hostdex.jar"
done

echo "== compile-time class stubs (AOSP, OSS)"
declare -A JAVAC=(
  [core-oj]=libcore/core-oj
  [core-libart]=libcore/core-libart
  [core-icu4j]=external/icu/android_icu4j/core-icu4j
  [conscrypt]=external/conscrypt/conscrypt
  [okhttp]=external/okhttp/okhttp
  [bouncycastle]=external/bouncycastle/bouncycastle
)
for name in "${!JAVAC[@]}"; do
  f=$(find "$I/${JAVAC[$name]}/android_common/javac" -name '*.jar' 2>/dev/null | head -1)
  if [ -n "$f" ]; then
    cp "$f" "$STAGE/lib/compile/$name.jar"
  else
    echo "   (skip $name: no javac jar)"
  fi
done

echo "== dex toolchain (self-hosted: r8 + ECJ already dexed to run on ART)"
# The host build's r8.jar has .class files (runs on a JDK); the SDK needs the
# dexed form that runs on ART. minihub bootstraps both r8.dex.jar and
# ecj.dex.jar (OSS: R8 + Eclipse ECJ).
cp "$MINIHUB_TOOLS/r8.dex.jar" "$STAGE/lib/tools/r8.dex.jar"
cp "$MINIHUB_TOOLS/ecj.dex.jar" "$STAGE/lib/tools/ecj.dex.jar"

echo "== ICU data, tzdata, CA trust store"
cp "$H/com.android.i18n/etc/icu/"*.dat "$STAGE/lib/i18n/etc/icu/"
cp -a "$H/com.android.tzdata/etc" "$STAGE/lib/tzdata/"        # -> lib/tzdata/etc/tz/...
cp -a "$H/etc/security/cacerts" "$STAGE/lib/android/etc/security/"

# No prebuilt boot image: it embeds absolute dex paths and so is not
# relocatable. The driver builds one on demand into the per-install cache
# (`art compile-boot`).
rmdir "$STAGE/lib/boot" 2>/dev/null || true

echo "== docs, examples, tests, version"
cp -a "$REPO/sdk/share/examples" "$STAGE/share/examples"
cp "$REPO/sdk/tests/SelfTest.java" "$STAGE/tests/SelfTest.java"
cp "$REPO/sdk/tests/selftest" "$STAGE/tests/selftest"
chmod +x "$STAGE/tests/selftest"
cp "$REPO/sdk/VERSION" "$STAGE/VERSION"
cp "$REPO/DESIGN.md" "$STAGE/docs/DESIGN.md"
[ -f "$REPO/sdk/README.md" ] && cp "$REPO/sdk/README.md" "$STAGE/README.md"

echo "== pack"
TARBALL="$DIST/$NAME.tar.zst"
( cd "$DIST" && tar --zstd -cf "$NAME.tar.zst" "$NAME" )
echo "staged:  $STAGE"
echo "tarball: $TARBALL ($(du -h "$TARBALL" | cut -f1))"
du -sh "$STAGE" | sed 's/^/unpacked: /'
echo "10-assemble: OK"
