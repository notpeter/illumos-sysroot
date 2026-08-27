# Implementation status

[`new-plan.md`](new-plan.md) is the authoritative plan for this branch. The
objective is to rebuild the three defined x86 sysroot releases from pinned
vanilla illumos inputs and prove that each result is reproducible across clean
OmniOS builders.

This document records the current repository state and the remaining work. It
does not override the locked decisions in `new-plan.md`.

## Release set

| Profile | Gate source | Publication state | Reproducibility state |
| --- | --- | --- | --- |
| `20181213` | [`sysroot/20181213`](https://github.com/illumos/illumos-gate/tree/sysroot/20181213) at `6265851cb0eea0e24c694164ca91635b4d414876`, release base `de6af22ae73ba8d72672288621ff50b88f2cf5fd` | [`20181213-de6af22ae73b-v2`](https://github.com/gwr/sysroot/releases/tag/20181213-de6af22ae73b-v2) is a `gwr/sysroot` prerelease; upstream still publishes v1 | Not yet rebuilt by the generalized pipeline |
| `20210501` | [`sysroot/20210501`](https://github.com/illumos/illumos-gate/tree/sysroot/20210501) at `e0b4275f346eda86b39157cd7dd3cc889a1f6988` | [`20210501-e0b4275f34-v0`](https://github.com/illumos/sysroot/releases/tag/20210501-e0b4275f34-v0) became the latest official release on 2026-08-23 | Published artifact exists; independent deterministic rebuild remains to be proved |
| `20231226` | stock gate at `ae676b1204fb703d5b394f9f8d947ef6210f3c3f` | Proposed `20231226-ae676b1204fb-v1`; not an upstream release | Full `repo.redist` and archive matched across two OmniOS r151046 builders; the durable toolchain lock is not implemented |

The official 20210501 asset has SHA-256
`28d8f4f6d84331ff1e99ac3d68b917cf8174897a5c00171c5e493253eb1587f6`.
The 20181213-v2 prerelease has SHA-256
`b09f1b240421228878cae608ab0b25a905900d1d5b70032b4aba15e0e7a8edc5`.

Upstream [PR #4](https://github.com/illumos/sysroot/pull/4) and
[PR #5](https://github.com/illumos/sysroot/pull/5) are merged. Do not describe
the 20210501 work as a draft or a prerelease. [Issue
#3](https://github.com/illumos/sysroot/issues/3) remains open and provides
consumer context, but it is not the release specification for this branch.

## What is already implemented

- `profiles/{20181213,20210501,20231226}.mk` pin archive names, gate commits,
  package sets, shim symbol level, and `SOURCE_DATE_EPOCH`.
- `env/illumos.<DATE>.sh` records the nightly environment for each gate.
- `mf2tar` normalizes tar metadata and emits deterministic gzip output.
- `scripts/fingerprint-repo-redist.sh` fingerprints the complete IPS
  repository, not only the packages selected for the sysroot.
- `scripts/check-repo-redist-repro.sh` performs two clean builds and compares
  the archive, paths, files, payloads, manifests, and parsed package actions.
- `scripts/build-omnios-sysroot.sh` contains the reproducibility fixes proven
  for the 20231226/r151046 build.
- `scripts/assemble-sysroot-from-repo.sh` can assemble on a non-illumos host
  when the four shim objects are supplied as fixed inputs.
- `.github/workflows/omnios-archive.yml` provides a 20231226 smoke assembly and
  a manually dispatched r151046 full build.

The current full-build script and workflow are still specialized for gcc 10,
JDK 11, OmniOS r151046, and the 20231226 profile. Their acceptance of another
`-r` value does not yet make them a correct multi-release implementation.

## Required implementation work

Work in this order.

1. Generalize gate preparation and dependency checks from the 20231226
   gcc10/r151046 assumptions to the compiler, JDK, env file, and backport
   branch selected by each release profile.
2. Fetch and verify the stock closed-bins archive for each build. Record its
   URL and digest; do not use the build host's `/opt/onbld/closed` as an
   untracked input.
3. Define and generate one `toolchain.<DATE>.lock` per release. Each lock must
   identify the exact IPS package FMRIs and content needed for the primary
   compiler, JDK, onbld, GNU make, and their runtime closure.
4. Install the locked toolchain into a clean OmniOS VM without consulting a
   live publisher after the inputs have been acquired and verified.
5. Keep Rust/Cargo out of the gate-build toolchain. `mf2tar` still needs Rust
   during archive assembly; the current combined script must therefore
   separate gate inputs from assembly inputs or consume a pinned `mf2tar`
   binary.
6. Run the double-build and independent-builder validation for all three
   profiles. Preserve the fingerprints, archive hashes, toolchain locks, and
   closed-bins digests as release evidence.
7. Cross-link the required C smoke program against each archive and run it on
   an appropriate OmniOS target. Verify archive contents and shim symbol
   versions with the existing checks.
8. Update CI to exercise the three-profile matrix from locked inputs. Keep the
   ordinary installed-package assembly job explicitly labeled as a smoke test.

## Acceptance criteria

A profile is complete only when all of the following are true:

- the checkout is the pinned vanilla `illumos-gate` commit or named
  `sysroot/<DATE>` backport branch;
- the closed bins, compiler, JDK, onbld tools, package closure, and
  `SOURCE_DATE_EPOCH` are recorded and content-verified;
- two clean builds on one builder produce identical `repo.redist` fingerprints
  and archive hashes;
- a clean build on a second builder produces those same hashes;
- `libssp_ns.a`, the crt objects, headers, libraries, and four shims pass the
  content and symbol checks described in [`new-plan.md`](new-plan.md);
- a linked smoke binary runs on illumos;
- the archive contains the five profile packages and excludes executable and
  administrative trees;
- the release evidence is sufficient for a third party to repeat the build.

For 20181213-v2, also compare the result with the published prerelease and
classify every difference. For 20210501-v0, compare against the official asset
hash above. A deterministic rebuild that intentionally differs from a
published artifact must not silently reuse its release identity.

## Known repository inconsistencies

- `profiles/20181213.mk` records `de6af22ae73b`, the release base, while the
  required build checkout is `sysroot/20181213` at `6265851cb0ee`. The current
  build script fetches `GATE_COMMIT` directly and therefore omits the six
  build-branch commits. The profile/schema must distinguish release base from
  pinned build head before the 2018 run.
- `env/illumos.20210501.sh` currently selects gcc 7 and **JDK 11**. That file,
  not the Java-8 entry in the current `new-plan.md` matrix, describes the
  checked-in build environment and must be reconciled before locking the 2021
  toolchain.
- `scripts/build-omnios-sysroot.sh -i` and the full-build workflow still
  install Rust because they also assemble the archive. This is not the final
  gate-only toolchain defined by the new plan.
- The workflow's archived `.p5p` package closure is useful development work,
  but it is not yet the per-release, URL-and-content-verified lock format.
- The 20231226 reproducibility proof used r151046 inputs. It does not establish
  that arbitrary future OmniOS package snapshots reproduce the same output.

## Deferred work

The scoped `usr/src/lib` + `usr/src/head` + crt build, zlib, OpenSSL, and a C++
runtime are outside the current release program. Future base-commit selection
policy is also separate from reproducing the three fixed profiles; see
[`base-commit-candidates.md`](base-commit-candidates.md).
