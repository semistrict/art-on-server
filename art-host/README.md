# art-host

Fork of ART's host build, ported to **arm64 Linux** (and then statically
linked). The upstream AOSP host build only supports x86_64-glibc; this repo
holds the idempotent scripts and the patch series that make `dalvikvm` /
`dex2oat` / `libart` build and run natively on an aarch64 Linux host — no
bionic chroot, no apexes, no Android device image.

Runs in the same Lima VM (`art`) as ~/src/art-server. Source tree lives
in-VM at `/opt/aosp/main-art` (AOSP `main-art` manifest).

## Plan

1. `scripts/10-sync.sh` — repo init/sync `main-art` (partial clone)
2. `scripts/20-inventory.sh` — what does the tree already support?
   (Soong arch combos, prebuilt toolchain arches, musl sysroots,
   `art_static_defaults`, `build_linux_bionic.sh`)
3. strategy decision: native toolchain transplant vs `linux_musl-arm64`
   host-cross vs new `linux_glibc-arm64` config
4. iterate to a working host `dalvikvm` on arm64
5. run the art-server + minihub test suites against it
6. static-link

Patches against AOSP projects live in `patches/<project-path>/*.patch`,
applied idempotently after sync.

## Usage

```sh
./run.sh            # everything up to the current frontier, idempotent
```
