# Release base provenance

The current work does not need to select another gate commit. The three
profiles and their release identities are fixed in [`plan.md`](plan.md):

| Profile | Vanilla gate base | Build branch or commit | Why it is in scope |
| --- | --- | --- | --- |
| `20181213` | `de6af22ae73ba8d72672288621ff50b88f2cf5fd` | [`sysroot/20181213`](https://github.com/illumos/illumos-gate/tree/sysroot/20181213) at `6265851cb0eea0e24c694164ca91635b4d414876` | Reproduce the v2 archive that adds `system/library/security/gss` to the original release |
| `20210501` | `2ed5ea5a06df7f669d20d88729c625981a0de7bc` | [`sysroot/20210501`](https://github.com/illumos/illumos-gate/tree/sysroot/20210501) at `e0b4275f346eda86b39157cd7dd3cc889a1f6988` | Reproduce the official 20210501-v0 release, including its build-only backport |
| `20231226` | `ae676b1204fb703d5b394f9f8d947ef6210f3c3f` | the commit directly; no backport branch currently exists | Prove a newer proposed release with the same deterministic process |

All payloads must be compiled from these illumos trees. OmniOS or Helios may
provide build tools, but their prebuilt `system/*` packages are not release
inputs.

## Current upstream state

- The illumos project published
  [`20210501-e0b4275f34-v0`](https://github.com/illumos/sysroot/releases/tag/20210501-e0b4275f34-v0)
  on 2026-08-23. It is no longer a draft or fork-only prerelease.
- The release was produced by merged [PR
  #5](https://github.com/illumos/sysroot/pull/5), after the libgss change in
  [PR #4](https://github.com/illumos/sysroot/pull/4) was also merged.
- The official 20210501 asset SHA-256 is
  `28d8f4f6d84331ff1e99ac3d68b917cf8174897a5c00171c5e493253eb1587f6`.
- The `gwr/sysroot`
  [`20181213-de6af22ae73b-v2`](https://github.com/gwr/sysroot/releases/tag/20181213-de6af22ae73b-v2)
  prerelease adds `libgss` to the upstream v1 package set. Its asset SHA-256 is
  `b09f1b240421228878cae608ab0b25a905900d1d5b70032b4aba15e0e7a8edc5`.
- `20231226-ae676b1204fb-v1` is defined only by this branch. It is not an
  illumos release and must not be documented as one until upstream publishes
  it.

## IPD 59 and release identity

[IPD 59](https://github.com/illumos/ipd/blob/master/ipd/0059/README.adoc)
defines the illumos project's recurring sysroot selection procedure. For
publication year `Y`, its base is the last gate commit before 1 May of
`Y - 3`, with build-only changes placed on `sysroot/<DATE>`.

The official 20210501 release follows that policy: its vanilla base is the
last qualifying 2021 commit, and `e0b4275f34` adds the pyzfs build backport.
The archive name uses the selected date and backport branch head.

The 20181213 build branch is six commits ahead of its vanilla base: five
backported gate fixes plus the sysroot build configuration commit. The release
identity remains based on `de6af22ae73b`; the reproducible checkout must still
pin and build the branch head `6265851cb0ee`.

The 20231226 profile came from an earlier support-window experiment: choose the
newest gate present in both the oldest supported OmniOS LTS and the platform
contemporary with the oldest supported SmartOS pkgsrc LTS. In the 2026 data,
SmartOS platform image 20231228 was the binding input and selected
`ae676b1204`. That experiment explains the existing profile; it is **not** an
adopted replacement for IPD 59.

The three-release reproducibility work should not be blocked on changing the
future selection policy. If 20231226 is proposed upstream, the difference from
IPD 59 must be explicit in that proposal.

## Verifying a release base

Use commit identity, not distribution package version strings, as the primary
record:

```sh
git clone https://github.com/illumos/illumos-gate
cd illumos-gate
git fetch origin refs/heads/sysroot/20181213:refs/remotes/origin/sysroot/20181213
git fetch origin refs/heads/sysroot/20210501:refs/remotes/origin/sysroot/20210501

git show --no-patch --format=fuller de6af22ae73ba8d72672288621ff50b88f2cf5fd
git show --no-patch --format=fuller e0b4275f346eda86b39157cd7dd3cc889a1f6988
git show --no-patch --format=fuller ae676b1204fb703d5b394f9f8d947ef6210f3c3f
```

For a backport branch, verify both the pinned branch head and its vanilla base:

```sh
git merge-base origin/master origin/sysroot/20210501
git log --oneline 2ed5ea5a06df..origin/sysroot/20210501
```

Release evidence must record:

- the full base and branch-head commit IDs;
- the complete patch series above the vanilla base;
- confirmation that every patch is build-only and does not change the API or
  ABI represented by the sysroot;
- the stock closed-bins archive URL and digest;
- the per-release toolchain lock and `SOURCE_DATE_EPOCH`;
- the resulting repository fingerprints and archive digest.

## Future selection work

Do not extend the old distribution tables in this file during the current
three-release effort. When selecting a later release:

1. start from the then-current IPD 59 text;
2. verify OmniOS support dates and SmartOS/pkgsrc assumptions from current
   primary sources;
3. identify the exact gate commit and build host toolchain;
4. propose any policy deviation upstream before assigning a release identity;
5. add a profile only after the selection is agreed.

OpenIndiana and Helios are useful compatibility targets, but historically did
not bind the x86 base selection because both tracked newer gate commits.
AArch64 has no release profile in this repository and is outside this work.
