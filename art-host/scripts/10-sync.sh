#!/usr/bin/env bash
# In-VM (run as the normal user, NOT root): sync the AOSP main-art manifest.
# Idempotent: repo sync resumes/refreshes.
set -euo pipefail

AOSP=/opt/aosp/main-art

# deps (repo launcher needs python3; sync needs git, curl)
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git python3 curl zip unzip rsync >/dev/null
if ! command -v repo >/dev/null; then
  sudo curl -fsSL -o /usr/local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo
  sudo chmod +x /usr/local/bin/repo
fi

# repo wants a git identity
git config --global user.email >/dev/null 2>&1 || git config --global user.email "ramon@echophase.com"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "Ramon Nogueira"
git config --global color.ui false

sudo mkdir -p "$AOSP"
sudo chown "$(id -u):$(id -g)" /opt/aosp "$AOSP"
cd "$AOSP"

# NOTE: the ART-only manifest kept its legacy name: "master-art" (there is no
# "main-art"; "master-art-host" is an obsolete stub pointing at a
# Google-internal manifest).
if [ ! -d .repo ]; then
  repo init -u https://android.googlesource.com/platform/manifest -b master-art \
    --partial-clone --clone-filter=blob:limit=10M --no-use-superproject </dev/null
fi

repo sync -c -j8 --no-tags --force-sync </dev/null

echo "=== sync done; tree size:"
du -sh "$AOSP"
ls "$AOSP"
echo "10-sync: OK"
