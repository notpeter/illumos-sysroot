# Reproducible illumos sysroot release plan

This is the authoritative plan for the `2026_updates` branch. It combines the
release requirements, current implementation status, remaining work, and
acceptance criteria for deterministically rebuilding the three defined x86
sysroot releases from pinned vanilla illumos inputs.

The intended builders are local OmniOS VMs and `vmactions/omnios-vm`. The final
archives must be byte-reproducible across clean builders and independently
verifiable. The payload must come from the pinned illumos-gate source, never
from a distribution's prebuilt `system/*` packages.

## Release set and current status

The release base identifies the API and ABI exposed by the archive. A build
head may add build-only backports needed to compile that base on the selected
host; the two values must be recorded separately.

| Profile | Release base and build source | Build environment | Publication state | Reproducibility state |
| --- | --- | --- | --- | --- |
| `20181213` | Base `de6af22ae73ba8d72672288621ff50b88f2cf5fd`; [`sysroot/20181213`](https://github.com/illumos/illumos-gate/tree/sysroot/20181213) build head `6265851cb0eea0e24c694164ca91635b4d414876` | Locked OmniOS r151030, gcc 4.4.4, JDK 8 package closure | [`20181213-de6af22ae73b-v2`](https://github.com/gwr/sysroot/releases/tag/20181213-de6af22ae73b-v2) is a `gwr/sysroot` prerelease; upstream publishes v1 | Exact offline requested-package and 143-FMRI runtime-closure verification passes; full reproducibility evidence is in progress |
| `20210501` | Base `2ed5ea5a06df7f669d20d88729c625981a0de7bc`; [`sysroot/20210501`](https://github.com/illumos/illumos-gate/tree/sysroot/20210501) build head `e0b4275f346eda86b39157cd7dd3cc889a1f6988` | Locked OmniOS r151038, gcc 7, JDK 11 package closure | [`20210501-e0b4275f34-v0`](https://github.com/illumos/sysroot/releases/tag/20210501-e0b4275f34-v0) is the latest official release; deterministic rebuilds use v1 | Exact offline requested-package and 157-FMRI runtime-closure verification passes; full reproducibility evidence is in progress |
| `20231226` | Stock gate commit `ae676b1204fb703d5b394f9f8d947ef6210f3c3f`; no build-backport branch | Locked OmniOS r151046, gcc 10, JDK 11 package closure | Proposed `20231226-ae676b1204fb-v1`; not an upstream release | Three corrected clean builds match across the primary and independent builders; repository and archive reproducibility plus Helios acceptance pass |

The profile-pinned normalization values are:

| Profile | `TARVERSION` | `SOURCE_DATE_EPOCH` | `LIBGCC_VERSION` |
| --- | --- | --- | --- |
| `20181213` | `20181213-de6af22ae73b-v3` | `1544726597` | `4_8_0` |
| `20210501` | `20210501-e0b4275f34-v1` | `1762459338` | `4_8_0` |
| `20231226` | `20231226-ae676b1204fb-v1` | `1703608857` | `4_8_0` |

`SOURCE_DATE_EPOCH` is a canonical value pinned by each release profile. It is
not necessarily the timestamp of the release-base or build-head commit and
must not be recomputed during a build.

The official 20210501 asset has SHA-256
`28d8f4f6d84331ff1e99ac3d68b917cf8174897a5c00171c5e493253eb1587f6`.
The 20181213-v2 prerelease has SHA-256
`b09f1b240421228878cae608ab0b25a905900d1d5b70032b4aba15e0e7a8edc5`.
Its two `lib/llib-lm.ln` payloads embed the original absolute build path
`/ws/oldgate`; the v3 profile excludes those non-runtime proprietary lint
objects and therefore deliberately uses a new release identity.

Upstream [PR #4](https://github.com/illumos/sysroot/pull/4) and
[PR #5](https://github.com/illumos/sysroot/pull/5) are merged. Do not describe
the 20210501 work as a draft or prerelease. [Issue
#3](https://github.com/illumos/sysroot/issues/3) remains open and provides
consumer context, but it is not the release specification for this branch.

## Locked requirements

1. Build all three releases from their pinned vanilla illumos-gate source.
   Build-only backports must not change the exposed payload API or ABI.
2. Use OmniOS builders. Use r151046 for the proven 20231226 path; do not claim
   that arbitrary future OmniOS package snapshots produce the same result.
3. Fetch the stock closed-bins archive for each build and record its URL and
   digest. Do not use an untracked host copy from `/opt/onbld/closed`.
4. Preserve each profile's checked-in `SOURCE_DATE_EPOCH` and derive the
   illumos `RELEASE_DATE` embedded in binaries from it. Pin `VERSION` and
   `BUILDVERSION_EXEC`; do not let `git describe` choose an abbreviation from
   the builder's local object database.
5. Run the Java-enabled full nightly build using the compiler and JDK selected
   by the release environment. Shadow compilation may be disabled because it
   does not contribute primary build output.
6. Keep Rust and Cargo out of the gate-build toolchain. Archive assembly still
   needs Rust when building `mf2tar` from source, so gate and assembly inputs
   must be separated or assembly must use a pinned `mf2tar` binary.
7. Include exactly `system/header`, `system/library`,
   `system/library/math`, `system/library/c-runtime`, and
   `system/library/security/gss` from the built `repo.redist`.
8. Define one `toolchain.<DATE>.lock` per release. Each lock must identify the
   exact compiler, JDK, onbld, GNU make, supporting tools, runtime closure,
   source URLs, package FMRIs, and content hashes.
9. Acquire and verify the locked inputs before installing them into a clean VM;
   the installation step must not consult a live publisher. If a historical
   compiler or JDK is no longer retained, preserve a content-verified `.p5p`
   as the durable input.
10. Build the four versioned shim libraries with pinned inputs and consistently
    assemble the non-debug (`nightly-nd`) package repository.

The sysroot payload includes headers, shared libraries, C runtime objects, and
four generated 32/64-bit `libgcc_s` and `libssp` shims.  The 20210501 and
20231226 gates also provide `libssp_ns.a`.  The pinned 20181213 gate has no
`ssp_ns` source or package action, and the published 20181213-v2 archive does
not contain that library; its reproducibility criterion is therefore matching
absence, not fabricating a file outside the release source.  `mf2tar` already
normalizes tar metadata and entry order, while `gzip -n` normalizes the gzip
envelope. Reproducibility also requires the underlying gate-built binary
payload to match.

## Implemented state

- `profiles/{20181213,20210501,20231226}.mk` define archive names, package
  sets, shim symbol levels, and normalization epochs.
- `env/illumos.<DATE>.sh` records the nightly environment for each gate.
- `mf2tar` normalizes archive metadata and emits deterministic gzip output.
- `scripts/fingerprint-repo-redist.sh` fingerprints the complete IPS
  repository, not only the packages selected for the sysroot.
- `scripts/check-repo-redist-repro.sh` performs two clean builds and compares
  archive hashes, paths, files, payloads, manifests, and parsed package
  actions.
- `scripts/build-omnios-sysroot.sh` contains the reproducibility fixes proven
  for the 20231226/r151046 build and release-specific compatibility for the
  pinned r151030 and r151038 gates.
- `locks/toolchain.<DATE>.lock` records the exact requested FMRIs,
  builder-selected runtime closure, builder image, gate source, closed bins,
  Rust version, and every archived kit artifact.
  `scripts/install-omnios-toolchain.sh` installs only the requested packages
  with live publishers disabled, then verifies the complete exact closure.
- `scripts/validate-release-lock.sh` checks each profile against its lock
  without requiring an OmniOS builder.
- `scripts/assemble-sysroot-from-repo.sh` assembles on a non-illumos host when
  the four shim objects are supplied as fixed inputs.
- `.github/workflows/omnios-archive.yml` validates all three locked profiles,
  provides a 20231226 installed-package smoke assembly, and recreates and
  replays the exact r151046 kit for a manually dispatched full build.
- An earlier 20231226 proof compared 807 directories and 24,012 files and
  passed the Helios smoke, but shared an unpinned `RELEASE_DATE` and
  clone-dependent `git describe` abbreviation.  Corrected reruns supersede
  those hashes.

The full-build script is profile-driven for all three releases. Hosted
`vmactions/omnios-vm` full-build coverage remains r151046-only because its
available images do not include r151030 or r151038; the three-profile CI
matrix therefore performs lock validation, while historical full builds run
on locally preserved OmniOS builders.

## Required implementation work

Work in this order:

1. Extend the profile schema to distinguish the release base from the pinned
   build head. Correct the 2018 checkout to use build head `6265851cb0ee` while
   retaining `de6af22ae73b` in the release identity.
2. Generalize gate preparation and dependency checks from the 20231226
   gcc10/r151046/JDK11 assumptions to the compiler, JDK, environment file,
   build source, and builder selected by each profile.
3. Fetch and verify the stock closed-bins archive for every release and record
   its URL and digest as a build input.
4. Define and generate the three toolchain locks, including the transitive IPS
   runtime closure. Implement fetch, content verification, cache validation,
   and offline installation into a clean OmniOS VM.
5. Separate the gate-only toolchain from archive-assembly inputs. Add a guard
   that fails if the pinned gate contains `*.rs` or `Cargo.toml`.
6. Run same-builder double builds and independent-builder builds for all three
   profiles. Preserve repository fingerprints, archive hashes, toolchain
   locks, closed-bins digests, and builder identities as release evidence.
7. Cross-link the required C smoke program against every archive and run it on
   an appropriate OmniOS target. Verify archive contents, library symlinks,
   crt objects, `libssp_ns.a`, and shim symbol versions.
8. Compare 20181213-v2 and 20210501-v0 with their published artifacts and
   classify every difference. A deterministic payload that differs from a
   published artifact must receive a new release identity rather than silently
   reuse the old one.
9. Convert CI to a three-profile matrix driven by verified locked inputs. Keep
   the installed-package assembly job explicitly labeled as a smoke test.

## Acceptance criteria

A profile is complete only when all of the following are true:

- The checkout is the recorded build head, and its relationship to the vanilla
  release base is documented.
- Closed bins, compiler, JDK, onbld tools, package closure, assembly tool, and
  `SOURCE_DATE_EPOCH` are content-verified and recorded.
- Two clean builds on one builder produce identical normalized `repo.redist`
  fingerprints, uncompressed tars, and compressed archive hashes.
- A clean build on a second builder produces those same fingerprints and
  hashes.
- The crt objects are byte-identical across builds.  `libssp_ns.a` is also
  byte-identical for 20210501 and 20231226; 20181213 must preserve its absence
  from the pinned source and published v2 archive.
- The archive contains `usr/include`, libraries under `usr/lib` and
  `usr/lib/amd64`, crt objects, both architectures of the `libgcc_s` and
  `libssp` shims, and `libgss`.  The 20210501 and 20231226 archives additionally
  contain both architectures of `libssp_ns.a`.
- The archive excludes `usr/bin`, `etc`, `var`, `usr/share`, `usr/sbin`,
  `usr/ccs`, `bin`, and `sbin`; every assembled library symlink resolves
  inside the extracted sysroot.  (`scripts/liblinks.sh` creates links; it is
  not a read-only validator.)
- The shims export the required `GCC_4.8.0` and `LIBSSP_1.0` symbol versions
  and pass native illumos link checks.
- A C smoke program using libc, libm, libsocket, and libpthread cross-links
  against the archive with `--sysroot` and runs successfully on illumos.
- The source tree passes the Rust-absence guard and every payload package came
  from the pinned gate build rather than a Helios or OmniOS `system/*`
  package.
- Release evidence is sufficient for a third party to acquire the recorded
  inputs and repeat the build without relying on a live package publisher.

For 20181213-v2, compare with the `gwr/sysroot` prerelease and classify every
difference. For 20210501-v0, compare with the official asset hash above. The
earlier 20231226 two-builder result is superseded because it used unpinned
release-date and gate-version inputs; only corrected lock-bound reruns count
toward the acceptance criteria.

## Verified technical findings

- The pinned gates contain no Rust source or Cargo manifests. Rust is an
  assembler build dependency, not a gate build dependency.
- Full nightly builds include Java consumers such as `poold` and the DTrace
  Java API, so the release-specific JDK remains required.
- The 2018 gate's normal install recipes invoke proprietary Sun Studio `lint`
  even when the nightly does not request a lint pass.  Profiles bind
  `BUILD_LINT` to a reproducible placeholder generator.  The selected 2018
  package set contains one such historical lint library, so it must be
  excluded from a new deterministic archive or treated as a classified
  difference from the published v2 payload.
- The published 20181213-v2 ELF comments identify gate source
  `ea9f1efc2e` and `April 2020`; that object is absent from the retained
  `sysroot/20181213` history.  The reproducible v3 profile records the current
  branch head `6265851cb0ee` and a fixed `December 2018` release date.
- illumos embeds `RELEASE_DATE` in gate-built ELF files.  The published
  20210501-v0 payload records `February 2026`; deterministic rebuilds derive
  `November 2025` from the profile epoch and therefore use the v1 identity.
- The default nightly environment derives `VERSION` and build-version strings
  with `git describe`, whose abbreviation length depends on the local object
  database.  Each profile records a complete fixed value instead.
- illumos `ar` is nondeterministic, but the only payload archive,
  `libssp_ns.a`, is copied from GCC rather than constructed by this gate build.
  Pinning and directly comparing that input is therefore the required check
  for the two profiles whose gates include it.  The 20181213 source and
  published v2 artifact both omit it.
- IPS file actions in the selected packages do not carry source timestamps;
  applying the profile's normalization epoch does not discard package mtime
  metadata.
- The selected package set covers the core illumos libraries and the default
  Rust illumos link requirements. Toolchain repositories may supply build
  tools only; they must never supply the sysroot's `system/*` payload.

## Candidate Java-free native build path

The current release proof deliberately uses a Java-enabled full nightly.  A
follow-on implementation may make a deliberately scoped native build the
primary source-to-sysroot path while retaining the full nightly as an
independent regression oracle:

```text
Java-enabled full nightly -> repo.redist --+
                                           +-> canonical selected payload
Java-free scoped build ----> proto area ---+          |
                                                      v
                                         common archive assembly -> sysroot
```

The equivalence boundary is the selected sysroot payload, not the complete
`repo.redist`.  A scoped build is expected to omit commands, Java components,
and packages that the nightly builds, so its complete intermediate output
cannot match the nightly repository.  It must instead reproduce every
selected directory, regular file, and link after applying the profile's five
package selections and path exclusions.  Regular-file contents and link
targets must match, as must the four shim inputs and the ordered action stream
used for archive assembly.

The scoped path must:

- start from the same pinned gate build head and use the same compiler,
  onbld tools, GNU make, release strings, normalization epoch, and relevant
  reproducibility wrappers as the full nightly;
- build and install `usr/src/head`, the crt objects, and the complete native
  dependency closure of the selected libraries into a clean proto area;
- skip Java-consuming commands rather than satisfy them with distribution
  binaries, and never source a selected `system/*` payload from the builder;
- express the selected proto contents as the same canonical action set used
  for the nightly extraction.  This may be a generated aggregate manifest, a
  minimal IPS repository, or another checked and deterministic representation;
- run the common `mf2tar`, shim-addition, and `gzip -n` assembly operation so
  tar entry ordering and metadata do not vary by producer path; and
- preserve enough dependency and command evidence to explain why building a
  smaller directory graph does not change the selected native objects.

Qualification should proceed in this order:

1. Derive a canonical selected-payload map from a clean full nightly.  Record
   each path's action type, content digest or link target, and originating
   package action after exclusions.
2. Discover and document the smallest clean native build closure that
   populates every path in that map.  Do not start from a proto area populated
   by a previous nightly.
3. Compare the scoped proto and nightly repository at the selected-payload
   boundary before archive creation.  A missing, additional, or byte-different
   selected object is a build-path failure.
4. Assemble both candidates with identical profile inputs and require the
   uncompressed tar and compressed archive hashes to match byte for byte.
5. Repeat the scoped build twice from clean paths and on an independent
   builder, then run the same content, native-link, and illumos runtime tests
   required of the nightly-produced archive.
6. Only after all three profiles satisfy those checks may the scoped path
   replace the full nightly as the release-producing path.

Repository differences outside the selected payload remain useful nightly
regression evidence, but are not a sysroot mismatch.  Conversely, identical
extracted trees with different tar hashes indicate a canonical assembly or
action-ordering defect and do not satisfy equivalence.

If qualified, the release lock can be split into a Java-free native-build lock
and a separate full-nightly regression lock that retains the JDK.  The full
nightly should continue periodically and before intentional payload changes;
its broad build and packaging result remains an independent check, but Java
availability would no longer gate ordinary sysroot production.

Removing closed bins is a separate qualification.  The scoped path may omit
them only after the canonical action map excludes the known closed payloads
and a clean dependency trace proves that no selected native object uses them
at build time.  Success in removing the JDK alone does not establish that
proof.

## Deferred and out of scope

- The candidate Java-free native path above is follow-on work.  It does not
  replace the Java-enabled nightly requirements or current acceptance criteria
  until it has passed the stated cross-path qualification for all profiles.
- zlib, OpenSSL, and the C++ runtime are not part of these releases. Consumers
  must provide them separately.
- The project guarantees reproducibility of the sysroot payload, not every
  artifact produced by a full illumos-gate nightly build.
- Future base-commit selection policy is separate from reproducing these three
  fixed profiles; see [`base-commit-candidates.md`](base-commit-candidates.md).
