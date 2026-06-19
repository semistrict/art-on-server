#!/usr/bin/env bash
# In-VM: provision runtime data files the thin master-art manifest cannot
# build (no system/timezone project): graft the tzdata module from the
# art-server chroot's extracted apex into the host out dir. Idempotent.
set -euo pipefail

AOSP=/opt/aosp/main-art
TZ_SRC=/opt/android/chroot/apex/com.android.tzdata
TZ_DST=$AOSP/out/host/linux-arm64/com.android.tzdata

[ -d "$TZ_SRC/etc/tz" ] || { echo "tzdata apex not found at $TZ_SRC (run art-server setup first)" >&2; exit 1; }

mkdir -p "$TZ_DST"
rsync -a "$TZ_SRC/etc" "$TZ_DST/"
ls "$TZ_DST/etc/tz/tzdata" >/dev/null

# CA trust anchors: conscrypt's TrustedCertificateStore reads
# $ANDROID_ROOT/etc/security/cacerts (host-art-run.sh sets ANDROID_ROOT to
# the host out dir). Take the standard set from the GSI chroot.
CA_SRC=/opt/android/chroot/system/etc/security/cacerts
CA_DST=$AOSP/out/host/linux-arm64/etc/security/cacerts
[ -d "$CA_SRC" ] || { echo "cacerts not found at $CA_SRC" >&2; exit 1; }
mkdir -p "$(dirname "$CA_DST")"
rsync -a --delete "$CA_SRC/" "$CA_DST/"
[ "$(ls "$CA_DST" | wc -l)" -gt 50 ]
echo "55-runtime-data: OK"
