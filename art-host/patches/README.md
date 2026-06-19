# Remaining patches

The forked AOSP projects are vendored as **full source** at the repo root (`art/`,
`libcore/`, `bionic/`, `external/musl/`, `external/conscrypt/`, `build/make/`,
`build/soong/`, `libnativehelper/`) — one directory per project, each change a
commit. See `git log -- <project>`.

Only two projects remain as patches here, because their on-disk size is dominated
by non-source data and committing the whole tree for a few changed files is
impractical:

| project | size | changed files | why a patch |
|---|---|---|---|
| `external/icu` | ~430 MB | 3 | mostly ICU locale data, not source |
| `prebuilts/rust` | ~13 GB | 1 | a prebuilt Rust toolchain, not source |

`art-host/scripts/35-stage-sources.sh` rsyncs the vendored source over the synced
AOSP tree and then applies these two patches (idempotently).
