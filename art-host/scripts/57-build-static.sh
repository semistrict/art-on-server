#!/usr/bin/env bash
# In-VM: build the fully static host binaries (dex2oats + dalvikvms).
# Two-pass: dalvikvms compiles in a table of the Java_* symbols exported by
# the boot JNI static archives (for lazy native-method resolution without
# dlsym), so build once, regenerate the table from the archives, and rebuild
# if it changed. Idempotent.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
AOSP=/opt/aosp/main-art
OUT_CPP=$AOSP/art/dalvikvm/static_jni_symbols.cpp

gen() { bash "$HERE/56-gen-static-jni-symbols.sh"; }
build() {
  TARGETS="out/host/linux-arm64/bin/dex2oats out/host/linux-arm64/bin/dalvikvms" \
    bash "$HERE/50-build-art.sh"
}

gen
before=$(md5sum "$OUT_CPP")
build
gen
after=$(md5sum "$OUT_CPP")
if [ "$before" != "$after" ]; then
  echo "static JNI table changed; rebuilding dalvikvms"
  build
fi
echo "57-build-static: OK"
