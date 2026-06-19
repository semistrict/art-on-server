#!/usr/bin/env bash
# In-VM: prove the natively-built host ART works end-to-end —
# javac (jdk21) -> d8 (built d8.jar) -> dalvikvm64 with the built hostdex
# bootclasspath and ICU data. Idempotent.
set -euo pipefail

AOSP=/opt/aosp/main-art
cd "$AOSP"

export ANDROID_HOST_OUT=$AOSP/out/host/linux-arm64
export ANDROID_I18N_ROOT=$ANDROID_HOST_OUT/com.android.i18n
export ANDROID_ART_ROOT=$ANDROID_HOST_OUT
export ANDROID_TZDATA_ROOT=$ANDROID_HOST_OUT/com.android.tzdata
export ANDROID_DATA=${ANDROID_DATA:-/tmp/host-art-smoke/android-data}

WORK=/tmp/host-art-smoke
mkdir -p "$WORK/classes" "$WORK/dex" "$ANDROID_DATA"

JDK=$AOSP/prebuilts/jdk/jdk21/linux-arm64
B=$ANDROID_HOST_OUT/framework
BCP=$B/core-oj-hostdex.jar:$B/core-libart-hostdex.jar:$B/core-icu4j-hostdex.jar:$B/okhttp-hostdex.jar:$B/bouncycastle-hostdex.jar:$B/apache-xml-hostdex.jar:$B/conscrypt-hostdex.jar

cat > "$WORK/Smoke.java" <<'EOF'
import java.time.ZonedDateTime;
import java.time.ZoneId;
import java.util.Locale;

public class Smoke {
    public static void main(String[] args) {
        // Exercise ICU (locale data) and core libs, not just println.
        String upper = "istanbul".toUpperCase(Locale.forLanguageTag("tr-TR"));
        if (!upper.equals("İSTANBUL")) {
            throw new AssertionError("ICU locale data broken: " + upper);
        }
        ZonedDateTime t = ZonedDateTime.now(ZoneId.of("UTC"));
        if (t.getYear() < 2026) {
            throw new AssertionError("clock/tz broken: " + t);
        }
        // Named zones come from the tzdata module (55-runtime-data.sh).
        ZonedDateTime ny = t.withZoneSameInstant(ZoneId.of("America/New_York"));
        int offsetHours = ny.getOffset().getTotalSeconds() / 3600;
        if (offsetHours != -4 && offsetHours != -5) {
            throw new AssertionError("tzdata broken: NY offset " + offsetHours);
        }
        System.out.println("SMOKE OK on " + System.getProperty("os.arch")
                + " vm=" + System.getProperty("java.vm.name")
                + " " + System.getProperty("java.vm.version"));
    }
}
EOF

"$JDK/bin/javac" -d "$WORK/classes" "$WORK/Smoke.java"
"$JDK/bin/java" -cp "$B/d8.jar" com.android.tools.r8.D8 \
  --output "$WORK/dex" "$WORK/classes/Smoke.class"

OUT=$("$ANDROID_HOST_OUT/bin/dalvikvm64" \
  -Xbootclasspath:"$BCP" \
  -Xnoimage-dex2oat \
  -cp "$WORK/dex/classes.dex" Smoke)
echo "$OUT"
case "$OUT" in
  *"SMOKE OK on aarch64"*) echo "60-smoke-host-art: OK" ;;
  *) echo "60-smoke-host-art: FAILED" >&2; exit 1 ;;
esac
