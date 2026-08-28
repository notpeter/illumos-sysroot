# Reproducibility model and validation

The release goal is stronger than deterministic tar creation: the selected
illumos source, complete gate output repository, sysroot payload, shims, and
archive envelope must all be reproducible from recorded public inputs.

[`plan.md`](plan.md) defines the required releases and acceptance
tests. This document describes the mechanisms already implemented, the proof
obtained so far, and the remaining boundary between development evidence and a
repeatable release process.

## Reproducibility boundary

A release is a function of these pinned inputs:

- the vanilla illumos-gate base and any `sysroot/<DATE>` build-only backports;
- the stock closed-bins archive;
- the primary compiler, JDK, onbld tools, GNU make, and their runtime closure;
- the nightly env file and release profile;
- the sysroot build scripts and `mf2tar` source or binary;
- the four shim inputs;
- `SOURCE_DATE_EPOCH` and the fixed gate version string.

The build host is an execution environment, not a source of payload. In
particular, the archive must not contain prebuilt `system/*` files from OmniOS,
Helios, or another distribution.

There are two independent deterministic stages:

1. **Gate output:** compile the pinned gate and produce a byte-identical
   `packages/i386/nightly-nd/repo.redist`.
2. **Archive assembly:** select the profile packages, add the four shims, and
   emit a byte-identical tar and gzip stream.

An identical archive from two different `repo.redist` trees is not enough;
the complete repository fingerprints are also compared so nondeterminism
outside the selected package subset remains visible.

## Proposed dual-path equivalence boundary

The candidate Java-free native path in [`plan.md`](plan.md) introduces a
second producer without weakening the existing nightly proof.  During its
qualification, the Java-enabled nightly remains the reference producer and
the scoped build is a candidate producer.  They converge at a canonical map
of the selected sysroot payload:

```text
reference: full nightly -> repo.redist -> selected action map
candidate: scoped native build -------> selected action map
                                             |
                                             v
                                    common archive assembly
```

The map is evaluated after selecting the five profile packages and applying
the profile exclusions.  For each surviving path it records at least:

- the action type: directory, regular file, or symbolic link;
- the normalized archive path;
- the regular-file content digest or symbolic-link target; and
- the originating package action, where the producer has IPS metadata.

Directory ownership and archive timestamps need not come from the producer;
`mf2tar` supplies the normalized archive metadata.  File bytes, membership,
link targets, shim digests, and action ordering are producer-independent
inputs to the common assembler and must match exactly.  If direct
manifest/proto mode and repository/package mode enumerate equivalent actions
in different orders, the assembler or its input manifest must canonicalize
that order before the paths can be considered byte-equivalent.

Comparison results have three different meanings:

| Difference | Interpretation |
| --- | --- |
| Selected path, file digest, or link target differs | The scoped build is incomplete or does not reproduce the nightly-built native payload. |
| Selected maps match but tar or gzip hashes differ | Archive metadata, action ordering, shim input, or compression is not canonical. |
| Only unselected `repo.redist` content differs | The nightly regression surface differs, but the sysroot payload still matches. |

The scoped path must begin with empty object and proto directories and invoke
the same native makefiles with the same pinned source, tools, flags, release
identity, and reproducibility wrappers.  Copying selected files out of a
previous nightly would test assembly only and cannot qualify the scoped build.

Cross-path equality is additional evidence, not a substitute for repeatability:
the scoped producer must also match across two clean paths on one builder and
an independent builder.  Both producer paths then run through the same archive
content checks, native link probes, and illumos runtime smoke.  Until all
profiles pass, the complete nightly `repo.redist` comparison remains the
release acceptance boundary described above.

## Release status

| Profile | Published comparison target | Gate/repository proof | Independent builder proof |
| --- | --- | --- | --- |
| `20181213` | `gwr/sysroot` v2, SHA-256 `b09f1b240421228878cae608ab0b25a905900d1d5b70032b4aba15e0e7a8edc5` | Two clean locked r151030 builds have identical complete repositories and v3 archive bytes; 143-FMRI closure and Helios checks pass | No second r151030 builder |
| `20210501` | official v0, SHA-256 `28d8f4f6d84331ff1e99ac3d68b917cf8174897a5c00171c5e493253eb1587f6` | Two clean locked r151038 builds have identical complete repositories and v1 archive bytes; 157-FMRI closure and Helios checks pass | No second r151038 builder |
| `20231226` | no published artifact | Three corrected clean builds have identical complete repository fingerprints and archive bytes | Matching locked builds on independent r151046 VMs |

An earlier 20231226 comparison found matching repositories and archives and
passed the Helios runtime smoke. That evidence is superseded: both builds
shared an unpinned wall-clock `RELEASE_DATE` and clone-dependent `git describe`
abbreviation. Only results produced after those values were profile-pinned
belong in the release evidence.

## Normalization implemented for locked profiles

The gate build uses `SOURCE_DATE_EPOCH` only when a release profile supplies
it. Reproducibility mode applies the following targeted transformations:

| Source of variation | Normalization |
| --- | --- |
| absolute gate checkout path in GCC output | compiler wrappers map debug paths; the gcc 4 and gcc 7 profiles also present source arguments and attached absolute `-I`, `-iquote`, and `-isystem` paths through release-specific stable gate symlinks because `-fdebug-prefix-map` does not rewrite `__FILE__`; the 2021 lexer input is likewise presented through the stable gate path |
| illumos release date in ELF comments | `RELEASE_DATE` is derived from `SOURCE_DATE_EPOCH` under the C locale |
| clone-dependent `git describe` output | profiles pin `VERSION` and use a fixed-output `BUILDVERSION_EXEC` wrapper |
| DTrace probe suffixes | a fixed suffix derived from `SOURCE_DATE_EPOCH` |
| DTrace `ftok()` keys | a small preload object returns the fixed release key |
| DTrace helper pointers | serialized `DOF_SECT_ACTDESC.dofa_uarg` fields are zeroed |
| DTrace host identity | DOF `utsname.nodename` is replaced with `illumos-sysroot` |
| JAR entry times and order | the JAR wrapper normalizes mtimes and repacks entries in deterministic order |
| SLP manifest build time | bracketed `Implementation-Version` timestamps are set from the release epoch |
| SQLite2 SMF seed databases | imports use a stable canonical XML path, followed by deterministic allocation state, final `VACUUM`, and a fixed schema cookie |
| pyzfs message catalog order | `xgettext` input is sorted under `LC_ALL=C` |
| Python bytecode filenames and headers | `compileall -s` stores 2021/2023 paths relative to the proto root; Python 3.5 in the 2018 builder uses `compileall -d .`; recognized legacy Python 2.7/3.5 bytecode timestamps are then set to the release epoch without modifying PEP 552 headers |
| JDK 8 Javadoc ordering | qualified and unqualified intra-class method-link labels are canonicalized; generated table rows and simple list items are bytewise sorted before publication, with row classes reassigned after sorting |
| 2018 spell hash tables | the table is zero-initialized before the historical bitwise population algorithm |
| IPS publication and catalog time | package tools run with a fixed UTC clock derived from the release epoch |
| Python hash iteration in IPS tools | controlled entry points and deterministic ordering |
| IPS search-index manifest IDs | FMRIs are sorted by canonical string before indexing |
| `libssp_ns.a` metadata | deterministic archive creation in reproducibility mode |
| tar ownership and time | `mf2tar` writes uid/gid 0 and the release epoch |
| gzip header | `gzip -n` omits variable name and timestamp fields |

These transformations are intended to remove host, path, process, and
wall-clock identity without changing the API or ABI represented by the release.
The build script applies only transformations supported by the selected gate
version and verifies each pinned checkout before modifying it.

## Complete repository comparison

On an appropriately provisioned OmniOS builder, run:

```sh
scripts/check-repo-redist-repro.sh \
    -r 20231226 \
    -w /path/to/clean-work \
    -o /path/to/evidence \
    -j 4
```

The default uses different absolute directories for run 1 and run 2. `-s`
reuses one path, deleting it between runs; that is a diagnostic mode and does
not replace the different-path test.

The comparison covers:

- `paths.all`, `paths.dirs`, `paths.files`, and `paths.links`;
- `files.sha256` for every repository file;
- `file-payloads.sha256` for content-addressed IPS payloads;
- `pkg-manifests.sha256`;
- `payload-actions.tsv`;
- the final sysroot archive checksum.

The script preserves each run's package manifests and repository metadata
under the evidence directory. A successful run leaves no mismatch `.diff`
files.

The build and comparison scripts are profile-driven for all three releases.
Historical full builds require the retained r151030 and r151038 local builders;
hosted CI only has a suitable image for r151046.

## Archive assembly from a fixed repository

`mf2tar` expects an IPS publisher root containing `file/` and `pkg/`. A normal
`pkgrecv` destination is one level higher, so pass
`$repo/publisher/$publisher`, not `$repo`.

On illumos, build shims and assemble directly:

```sh
gmake archive RELEASE=20231226 \
    ILLUMOS_PKGREPO=/path/to/repo.redist
```

With fixed shim objects, assembly can run on Linux or another non-illumos host:

```sh
scripts/extract-prebuilt-shims.sh \
    /path/to/reference-sysroot.tar.gz \
    /path/to/prebuilt-shims

scripts/assemble-sysroot-from-repo.sh \
    /path/to/repo.redist \
    /path/to/prebuilt-shims
```

The prebuilt directory must contain:

- `usr/lib/libgcc_s.so.1`;
- `usr/lib/amd64/libgcc_s.so.1`;
- `usr/lib/libssp.so.0.0.0`;
- `usr/lib/amd64/libssp.so.0.0.0`.

Portable assembly proves deterministic packaging of fixed files. It does not
prove the provenance or reproducibility of those files.

## Installed-package smoke path

For a quick assembly test on illumos:

```sh
repo=/tmp/sysroot-repo
pkgroot=$(RELEASE=20231226 scripts/receive-installed-packages.sh "$repo")
gmake archive RELEASE=20231226 ILLUMOS_PKGREPO="$pkgroot"
```

This validates `mf2tar`, profile selection, manifest traversal, shim creation,
and archive-content checks. The resulting archive contains distribution
packages installed on that host and is never a release candidate.

The ordinary `archive` job in `.github/workflows/omnios-archive.yml` is this
kind of smoke test. Its artifact name and documentation must continue to say
so.

## Per-release acceptance evidence

Preserve the following for each profile:

- full gate base and backport branch IDs;
- closed-bins URL and digest;
- `toolchain.<DATE>.lock` and all fetched package digests;
- release profile, env file, and `SOURCE_DATE_EPOCH`;
- both same-builder fingerprints;
- the independent-builder fingerprints;
- compressed and uncompressed archive hashes;
- extracted hashes for `libssp_ns.a` and the crt objects;
- archive member list and shim `pvs -dsv` output;
- cross-link command and runtime smoke output;
- comparison with the published artifact for 20181213 and 20210501.

Do not claim a published artifact was reproduced merely because its contents
look equivalent. The compressed SHA-256 must match. If it does not, compare the
uncompressed tar, then member metadata and payload hashes, and assign a new
canonical identity if the deterministic result is intentionally different.

## Remaining gaps

- A second r151030 and r151038 builder is still needed for independent-builder
  proof of those profiles.
- Preserve the large p5p kits and complete fingerprint manifests with the
  release artifacts; they are intentionally not stored in Git.
- The manual hosted full-build workflow has not yet produced an Actions result
  from the checked-in locks.

The full gate need not be rebuilt in ordinary pull-request CI. It may be a
manual or release workflow, but it must consume immutable inputs and preserve
its evidence. Cheap archive assembly and content checks should continue to run
on normal changes.
