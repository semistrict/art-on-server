#!/usr/bin/env bash
# Run a Java program on the natively built host ART (linux_musl-arm64).
# Usage: host-art-run.sh [dalvikvm options] -cp <dex jars> MainClass [args]
set -euo pipefail

AOSP=/opt/aosp/main-art
export ANDROID_HOST_OUT=$AOSP/out/host/linux-arm64
export ANDROID_ART_ROOT=$ANDROID_HOST_OUT
# conscrypt's TrustedCertificateStore: $ANDROID_ROOT/etc/security/cacerts
export ANDROID_ROOT=$ANDROID_HOST_OUT
export ANDROID_I18N_ROOT=$ANDROID_HOST_OUT/com.android.i18n
export ANDROID_TZDATA_ROOT=$ANDROID_HOST_OUT/com.android.tzdata
export ANDROID_DATA=${ANDROID_DATA:-/tmp/host-art-data}
mkdir -p "$ANDROID_DATA"

B=$ANDROID_HOST_OUT/framework
BCP=$B/core-oj-hostdex.jar:$B/core-libart-hostdex.jar:$B/core-icu4j-hostdex.jar:$B/okhttp-hostdex.jar:$B/bouncycastle-hostdex.jar:$B/apache-xml-hostdex.jar:$B/conscrypt-hostdex.jar
# child dalvikvms (e.g. the minihub maven plugin's forks) pick the boot
# class path up from the environment
export BOOTCLASSPATH=$BCP

exec "$ANDROID_HOST_OUT/bin/dalvikvm64" \
  -Xbootclasspath:"$BCP" \
  -Xnoimage-dex2oat \
  "$@"
