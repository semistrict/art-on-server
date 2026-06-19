#!/usr/bin/env bash
# In-VM: regression test for the large-heap card-table stability fix.
#
# With native pointer-width references the heap maps anywhere in the 64-bit
# address space. The card table covers [min space Begin, max space Limit) over
# the continuous spaces, so if the non-moving space and the main/region space
# land far apart the card table balloons. Before the fix the main space was
# mapped with only a placement *hint*, which the kernel honoured only
# sometimes; when it didn't, the spaces ended up ~tens of TiB apart and heap
# init aborted with:
#   card_table.cc:67 Check failed: mem_map.IsValid() couldn't allocate card
#   table: Failed anonymous mmap(0, 274876805120, ...): Out of memory
# non-deterministically (it was observed ~4 startups in 6 under -Xgc:CMC).
#
# The fix carves the non-moving space and the main/region space out of a single
# contiguous reservation, so they are always virtually adjacent and the card
# table stays bounded regardless of where the reservation lands. The card table
# is created during heap init, before any class loads, so simply starting the
# runtime exercises the code path -- we don't need a workload, just many starts
# across a range of -Xmx values.
set -euo pipefail

AOSP=/opt/aosp/main-art
H=$AOSP/out/host/linux-arm64
# Default to the shipped static binary; override with BIN=.../dalvikvm64 etc.
BIN=${BIN:-$H/bin/dalvikvms}

export ANDROID_HOST_OUT=$H
export ANDROID_ART_ROOT=$H
export ANDROID_ROOT=$H
export ANDROID_I18N_ROOT=$H/com.android.i18n
export ANDROID_TZDATA_ROOT=$H/com.android.tzdata
export ANDROID_DATA=${ANDROID_DATA:-/tmp/host-art-data}
mkdir -p "$ANDROID_DATA"

B=$H/framework
BCP=$B/core-oj-hostdex.jar:$B/core-libart-hostdex.jar:$B/core-icu4j-hostdex.jar:$B/okhttp-hostdex.jar:$B/bouncycastle-hostdex.jar:$B/apache-xml-hostdex.jar:$B/conscrypt-hostdex.jar

ITERS=${ITERS:-20}
SIZES=${SIZES:-"1g 4g 8g 16g 32g"}

echo "--- card-table stability: $BIN"
echo "    $ITERS startups x sizes [$SIZES] under -Xgc:CMC -XX:LargeObjectSpace=map"

crash=0
init_ok=0
ram_limited=0
total=0
for xmx in $SIZES; do
  for i in $(seq 1 "$ITERS"); do
    total=$((total + 1))
    # A nonexistent main class makes the runtime fully initialise the heap
    # (card table included) and then fail to resolve the class -- exactly the
    # startup path we want to stress, with no workload dependency. -Xint isolates
    # the card table (created during heap init) from the separate >4 GiB JIT
    # reference-width limitation, so even multi-GB heaps init and fail cleanly.
    out=$("$BIN" -Xint -Xbootclasspath:"$BCP" -Xnoimage-dex2oat \
            -Xgc:CMC -XX:LargeObjectSpace=map -Xmx"$xmx" \
            __CardTableStabilityProbe__ 2>&1 || true)
    if echo "$out" | grep -qiE "couldn't allocate card table|card_table\.cc.*mem_map\.IsValid"; then
      crash=$((crash + 1))
      echo "  CARD-TABLE FAILURE at -Xmx$xmx run $i:"
      echo "$out" | grep -iE "card_table|mmap|Out of memory" | head -2 | sed 's/^/    /'
    elif echo "$out" | grep -qiE "ClassNotFound|__CardTableStabilityProbe__|Could not find|Unable to locate"; then
      # Heap initialised cleanly; class resolution then failed as expected.
      init_ok=$((init_ok + 1))
    elif echo "$out" | grep -qiE "main_mem_map_1\.IsValid|Failed.*mmap.*Out of memory"; then
      # The main-space mapping (PROT_READ|WRITE) exceeded host RAM+swap overcommit.
      # That is a resource limit of this machine, not a card-table/heap-layout
      # defect: the reservation succeeded, only committing the heap did not.
      ram_limited=$((ram_limited + 1))
    else
      # Some other early failure -- surface it; it must not be the card table.
      echo "  unexpected output at -Xmx$xmx run $i:" >&2
      echo "$out" | tail -3 | sed 's/^/    /' >&2
    fi
  done
done

echo "    heap-init-ok=$init_ok card-table-failures=$crash ram-limited=$ram_limited / $total starts"
if [ "$crash" -ne 0 ]; then
  echo "72-cardtable-stability: FAIL ($crash card-table allocation failures)" >&2
  exit 1
fi
if [ "$init_ok" -eq 0 ]; then
  echo "72-cardtable-stability: FAIL (no clean heap init observed; check setup)" >&2
  exit 1
fi
echo "72-cardtable-stability: PASS ($init_ok/$total clean heap inits, 0 card-table failures,"
echo "                             $ram_limited host-RAM-limited starts skipped)"
