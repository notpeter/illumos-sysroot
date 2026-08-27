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
| `20181213` | Base `de6af22ae73ba8d72672288621ff50b88f2cf5fd`; [`sysroot/20181213`](https://github.com/illumos/illumos-gate/tree/sysroot/20181213) build head `6265851cb0eea0e24c694164ca91635b4d414876` | OmniOS r151030-era gate defaults, JDK 8; exact compiler and package closure still need locking | [`20181213-de6af22ae73b-v2`](https://github.com/gwr/sysroot/releases/tag/20181213-de6af22ae73b-v2) is a `gwr/sysroot` prerelease; upstream publishes v1 | Not yet rebuilt by the generalized pipeline |
| `20210501` | Base `2ed5ea5a06df7f669d20d88729c625981a0de7bc`; [`sysroot/20210501`](https://github.com/illumos/illumos-gate/tree/sysroot/20210501) build head `e0b4275f346eda86b39157cd7dd3cc889a1f6988` | OmniOS r151038, gcc 7, JDK 11 as selected by `env/illumos.20210501.sh` | [`20210501-e0b4275f34-v0`](https://github.com/illumos/sysroot/releases/tag/20210501-e0b4275f34-v0) is the latest official release | Published artifact exists; independent deterministic rebuild remains to be proved |
| `20231226` | Stock gate commit `ae676b1204fb703d5b394f9f8d947ef6210f3c3f`; no build-backport branch | OmniOS r151046, gcc 10, JDK 11 | Proposed `20231226-ae676b1204fb-v1`; not an upstream release | Complete `repo.redist` trees and archives matched across two differently named and pathed r151046 builders; durable input locks remain incomplete |

The profile-pinned normalization values are:

| Profile | `TARVERSION` | `SOURCE_DATE_EPOCH` | `LIBGCC_VERSION` |
| --- | --- | --- | --- |
| `20181213` | `20181213-de6af22ae73b-v2` | `1544726597` | `4_8_0` |
| `20210501` | `20210501-e0b4275f34-v0` | `1762459338` | `4_8_0` |
| `20231226` | `20231226-ae676b1204fb-v1` | `1703608857` | `4_8_0` |

`SOURCE_DATE_EPOCH` is a canonical value pinned by each release profile. It is
not necessarily the timestamp of the release-base or build-head commit and
must not be recomputed during a build.

The official 20210501 asset has SHA-256
`28d8f4f6d84331ff1e99ac3d68b917cf8174897a5c00171c5e493253eb1587f6`.
The 20181213-v2 prerelease has SHA-256
`b09f1b240421228878cae608ab0b25a905900d1d5b70032b4aba15e0e7a8edc5`.

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
4. Preserve each profile's checked-in `SOURCE_DATE_EPOCH`.
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

The sysroot payload includes headers, shared libraries, C runtime objects,
`libssp_ns.a`, and four generated 32/64-bit `libgcc_s` and `libssp` shims.
`mf2tar` already normalizes tar metadata and entry order, while `gzip -n`
normalizes the gzip envelope. Reproducibility also requires the underlying
gate-built binary payload to match.

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
  for the 20231226/r151046 build.
- `scripts/assemble-sysroot-from-repo.sh` assembles on a non-illumos host when
  the four shim objects are supplied as fixed inputs.
- `.github/workflows/omnios-archive.yml` provides a 20231226 installed-package
  smoke assembly and a manually dispatched r151046 full build.
- The 20231226 proof compared 807 directories and 24,012 files across two
  builders. The all-files, payload, manifest, action, and final archive
  fingerprints matched, and the linked Helios smoke printed
  `illumos-sysroot-ok`.

The current full-build script and workflow remain specialized for gcc 10,
JDK 11, OmniOS r151046, and the 20231226 profile. Accepting another `-r` value
does not yet make them a correct multi-release implementation. The 20231226
result proves reproducibility from the preserved inputs used for that test; it
is not yet a durable third-party recipe because the toolchain lock and
closed-bins digest are not checked in.

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
- `libssp_ns.a` and the crt objects are byte-identical across builds.
- The archive contains `usr/include`, libraries under `usr/lib` and
  `usr/lib/amd64`, crt objects, both architectures of the `libgcc_s` and
  `libssp` shims, and `libgss`.
- The archive excludes `usr/bin`, `etc`, `var`, `usr/share`, `usr/sbin`,
  `usr/ccs`, `bin`, and `sbin`; `scripts/liblinks.sh` passes.
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
existing 20231226 two-builder result satisfies the build-output comparison,
native link, and runtime portions for the preserved r151046 input set; its
durable-input criteria remain open.

## Verified technical findings

- The pinned gates contain no Rust source or Cargo manifests. Rust is an
  assembler build dependency, not a gate build dependency.
- Full nightly builds include Java consumers such as `poold` and the DTrace
  Java API, so the release-specific JDK remains required.
- illumos `ar` is nondeterministic, but the only payload archive,
  `libssp_ns.a`, is copied from GCC rather than constructed by this gate build.
  Pinning and directly comparing that input is therefore the required check.
- IPS file actions in the selected packages do not carry source timestamps;
  applying the profile's normalization epoch does not discard package mtime
  metadata.
- The selected package set covers the core illumos libraries and the default
  Rust illumos link requirements. Toolchain repositories may supply build
  tools only; they must never supply the sysroot's `system/*` payload.

## Deferred and out of scope

- A deliberately scoped `usr/src/lib` + `usr/src/head` + crt build that skips
  Java-consuming commands is future work.
- zlib, OpenSSL, and the C++ runtime are not part of these releases. Consumers
  must provide them separately.
- The project guarantees reproducibility of the sysroot payload, not every
  artifact produced by a full illumos-gate nightly build.
- Future base-commit selection policy is separate from reproducing these three
  fixed profiles; see [`base-commit-candidates.md`](base-commit-candidates.md).
