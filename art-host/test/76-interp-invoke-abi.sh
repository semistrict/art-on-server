#!/usr/bin/env bash
# In-VM: regression test for the interpreter invoke-ABI under native pointer-width
# (8-byte) references. Covers the receiver/reference-width fixes that make real code
# run correctly on the interpreter:
#   - Class.newInstance() (deprecated, native Class_newInstance) receiver width,
#   - java.nio default FileSystemProvider init (uses Class.newInstance),
#   - non-static methods/constructors whose arguments spill past the argument
#     registers (QuickArgumentVisitor stack-arg stride for 8-byte references).
# See InterpInvokeAbi.java for the exact checks and expected values.
set -euo pipefail

AOSP=/opt/aosp/main-art
H=$AOSP/out/host/linux-arm64
BIN=${BIN:-$H/bin/dalvikvm64}

export ANDROID_HOST_OUT=$H
export ANDROID_ART_ROOT=$H
export ANDROID_ROOT=$H
export ANDROID_I18N_ROOT=$H/com.android.i18n
export ANDROID_TZDATA_ROOT=$H/com.android.tzdata
export ANDROID_DATA=${ANDROID_DATA:-/tmp/host-art-data}
mkdir -p "$ANDROID_DATA"

B=$H/framework
BCP=$B/core-oj-hostdex.jar:$B/core-libart-hostdex.jar:$B/core-icu4j-hostdex.jar:$B/okhttp-hostdex.jar:$B/bouncycastle-hostdex.jar:$B/apache-xml-hostdex.jar:$B/conscrypt-hostdex.jar

HERE=$(cd "$(dirname "$0")" && pwd)
JDK=$AOSP/prebuilts/jdk/jdk21/linux-arm64
WORK=/tmp/host-art-interp-abi
mkdir -p "$WORK/classes"

echo "--- compile InterpInvokeAbi.java -> dex"
"$JDK/bin/javac" -d "$WORK/classes" "$HERE/InterpInvokeAbi.java"
"$JDK/bin/java" -cp "$H/framework/d8.jar" com.android.tools.r8.D8 \
  --output "$WORK" --min-api 26 "$WORK"/classes/InterpInvokeAbi*.class

echo "--- run InterpInvokeAbi (-Xint, CMC)"
OUT=$("$BIN" -Xint -Xbootclasspath:"$BCP" -Xnoimage-dex2oat \
  -Xgc:CMC -XX:LargeObjectSpace=map -Xmx512m \
  -cp "$WORK/classes.dex" InterpInvokeAbi 2>&1)
echo "$OUT" | grep -vE "^06-|dalvikvm64:|dalvikvms:|mark_compact|tzdata|ICU|succeeded|APEX|u_set" | tail -2
echo "$OUT" | grep -q "INTERP-INVOKE-ABI OK"

echo "76-interp-invoke-abi: PASS"
