# Candidate illumos-gate base commits for sysroot releases

Working document. Goal: for each proposed sysroot "vintage", find the newest
`illumos-gate` commit that was present in *every* target distribution release,
since that commit is the newest base a sysroot can use without producing
binaries that fail to run on one of the targets.

## Method

Each distribution either builds `illumos-gate` directly or maintains a fork
that periodically merges from it. So for a given distro release, the newest
gate commit it contains is:

* **OmniOS** (`omniosorg/illumos-omnios`): `git merge-base illumos/master omnios/rNNNNNN`.
  OmniOS forks the gate into a release branch shortly before each release and
  thereafter only cherry-picks, so the merge-base does not move over the life
  of an LTS branch (verified: `r151046` has a 2023-03-24 merge-base and a
  2026-03-14 branch tip).
* **SmartOS** (`TritonDataCenter/illumos-joyent`): `git merge-base illumos/master joyent/release-YYYYMMDD`.
  There is one `release-` branch per biweekly platform image, and it tracks the
  gate to within a day or two.
* **OpenIndiana**: OI builds `illumos/illumos-gate` `master` at `HEAD` daily
  (see `components/openindiana/illumos-gate/Makefile` in `oi-userland`:
  `GIT_BRANCH=master`, `GIT_CHANGESET=HEAD`). The last component of OI's
  illumos package version is literally `git rev-list HEAD --count`, e.g.
  `system/kernel@0.5.11-2026.0.0.23228` == gate commit number 23228. Values
  below are gate `master` as of the ISO snapshot date; where an OI release-notes
  page names the commit explicitly it is used instead (agrees to within one or
  two commits).
* **Helios** (`oxidecomputer/illumos-gate`, branch `stlouis`):
  `git merge-base illumos/master oxide/stlouis@<build date>`. Oxide keeps
  `stlouis` merged up to gate `master` very closely, so the merge-base is
  usually the `stlouis` tip itself.

`illumos-gate` `master` is effectively linear (2 merge commits in ~23k), so
"newest commit common to all targets" is just the oldest of the per-distro
values. `n=` below is `git rev-list --count`, used as the ordering key.

Reproduce with:

```
git remote add omnios https://github.com/omniosorg/illumos-omnios
git remote add joyent https://github.com/TritonDataCenter/illumos-joyent
git remote add oxide  https://github.com/oxidecomputer/illumos-gate
git fetch --all
git merge-base origin/master omnios/r151054
```

## Selection policy

**Adopted policy (support-window variant of IPD 59).** For publication year
`Y`, take the newest gate commit present in both:

* the oldest OmniOS LTS still supported in `Y`, and
* the oldest SmartOS pkgsrc LTS still supported in `Y`, via the platform image
  contemporary with that LTS.

This replaces IPD 59's fixed "most recent commit before 1 May of `Y - 3`"
arithmetic while preserving its stated rationale, which is to cover "the oldest
supported LTS release from OmniOS, as well as the SmartOS LTS release against
which illumos pkgsrc is built". The build host is then the OmniOS LTS
contemporary with the chosen commit, which must ship gcc 10 or newer (r151046
or later); r151038 has only gcc 7 and is not usable for any commit from 2022
onwards.

OpenIndiana and Helios are not constraints under this policy: OI builds gate
`master` daily and Helios keeps `stlouis` merged up to `master`, so both are
always newer than either LTS bound. They are recorded below for completeness.

Applying it:

| Publish | Oldest OmniOS LTS | its gate | Oldest pkgsrc LTS | its PI | its gate | Base commit | Date | n | Build host |
| ------- | ----------------- | -------- | ----------------- | ------ | -------- | ----------- | ---- | - | ---------- |
| 2026 | r151054 | 2025-04-11 (n=22643) | 23.4.x | 20231228 | 2023-12-26 (n=21948) | `ae676b1204fb703d5b394f9f8d947ef6210f3c3f` | 2023-12-26 | 21948 | r151046 |
| 2027 | r151054 | 2025-04-11 (n=22643) | 24.4.x | 20241226 | 2024-12-19 (n=22474) | `fdb843bd8379b0c0e3bc04ffbd7cbbb10776afc2` | 2024-12-19 | 22474 | r151046 |
| 2028 | r151062 (projected 2027-05) | ~2027-03 | 25.4.x | 20260108 | 2026-01-05 (n=22853) | `29316b9c834da1aab0c095f56a69bd1e71121080` | 2026-01-05 | 22853 | r151054 |

SmartOS binds in every row, so the effective lookback is about two and a half
years rather than three or more, and it is set by pkgsrc's three-year LTS fix
window rather than by a calendar rule. Each base commit is comfortably newer
than the gate its build host ships, so these are forward builds and should not
need the kind of backport branches `sysroot/20181213` needed.

**Selected for the next release: `ae676b1204`, 2023-12-26**
(`profiles/20231226.mk`, `env/illumos.20231226.sh`, tag
`20231226-ae676b1204fb-v1`).

## Reference: newest common commit across contemporaneous releases

The tables below answer a different question, kept because it bounds how new a
sysroot could ever be: the newest gate commit common to the distribution
releases *of* a given year, with no support-window lookback at all. These are
not release candidates under the adopted policy.

| Vintage | Newest common gate commit | Commit date | n | Binding target |
| ------- | ------------------------- | ----------- | - | -------------- |
| 2018 (as shipped) | `de6af22ae73ba8d72672288621ff50b88f2cf5fd` | 2018-12-13 | 17732 | chosen, not maximal |
| 2018 (maximal) | `04e56356520b98d5a93c496b10f02530bb6647e0` | 2018-12-17 | 17737 | SmartOS PI 20181220 |
| 2019 | `f482e26cbeb654aaa01a12e3faae3878d6a59822` | 2019-01-15 | 17799 | SmartOS PI 20190117 |
| 2021 | `3714f7be8e09c39a0ea7ce7ef44cb495ce250913` | 2020-12-16 | 20193 | SmartOS PI 20201217 |
| 2023 | `b8af4a8966ef2150997d7664836f5c360b849005` | 2022-11-21 | 21378 | OpenIndiana 2022.10 |
| 2025 | `d3786586313a5c55c1a903b178111c096d216365` | 2024-10-23 | 22409 | Helios 20241023 |
| 2026 | `29316b9c834da1aab0c095f56a69bd1e71121080` | 2026-01-05 | 22853 | SmartOS PI 20260108 |

The shipped 2018 release is five commits older than the maximum those three
distributions allowed. That was deliberate: `de6af22ae7` is "9971 Make
getrandom(2) a public interface", the first commit of interest to land in
SmartOS PI 20181220. Rebuilding at `de6af22ae7` reproduces the published
archive exactly, which makes it the right smoke test for new tooling.

## Per-distribution data

### OmniOS

Release dates from <https://omnios.org/schedule>. LTS rows marked.

| Release | Type | Released | Newest gate commit | Commit date | n |
| ------- | ---- | -------- | ------------------ | ----------- | - |
| r151030 | LTS | 2019-05-06 | `fc8ae2ec4282de7ec96f48e11078345f3dc0ac3d` | 2019-03-28 | 18147 |
| r151032 | stable | 2019-11-04 | `814dcd43c3` | 2019-09-25 | 19064 |
| r151034 | stable | 2020-05-04 | `cd62a92d4a` | 2020-03-26 | 19559 |
| r151036 | stable | 2020-11-02 | `7bb0fe31b7` | 2020-09-28 | 20072 |
| r151038 | LTS | 2021-05-03 | `373fc975de7796bc28f551ba20f2d72b529dfe48` | 2021-03-26 | 20426 |
| r151040 | stable | 2021-11-01 | `938b2fd3f9` | 2021-09-28 | 20709 |
| r151042 | stable | 2022-05-02 | `5103e761e3` | 2022-03-30 | 21026 |
| r151044 | stable | 2022-11-07 | `17e9e0ae71` | 2022-09-28 | 21270 |
| r151046 | LTS | 2023-05-01 | `af2e290bb42516a18ceaf6aed43dd7e45c108b08` | 2023-03-24 | 21556 |
| r151048 | stable | 2023-11-06 | `cc7219b71d` | 2023-09-27 | 21812 |
| r151050 | stable | 2024-05-06 | `c46e4de36c` | 2024-03-20 | 22106 |
| r151052 | stable | 2024-11-04 | `e5d0cebc3b` | 2024-10-03 | 22381 |
| r151054 | LTS | 2025-05-05 | `4e6271a8389d5230e559fd147b6812f9b6122ff4` | 2025-04-11 | 22643 |
| r151056 | stable | 2025-11-03 | `9e324fa7fd` | 2025-10-02 | 22788 |
| r151058 | stable | 2026-05-04 | `9305420264` | 2026-03-27 | 22964 |

Note: r151058 is a *stable* release, not LTS. The current LTS is r151054
(supported to 2028-05-01); r151046 went EOL 2026-05-01.

### SmartOS

Important: the versions in the original request (`18.4.0`, `20.4.0`, `22.4.0`,
`24.4.1`, `25.4.0`) are **pkgsrc LTS zone images** (`base-64-lts`), where the
version is the pkgsrc release year and quarter; all Q4 pkgsrc releases are LTS.
Those images carry userland only. In a `joyent`-brand zone the illumos headers
and libraries come from the *platform image* running on the host, so the
platform image is what constrains an illumos sysroot. This also matches the
precedent set by `20181213-v1`, whose release notes cite platform images.

Below, each `base-64-lts` release is paired with the platform image that was
current on its release date.

| base-64-lts | Released | Contemporary platform image | Newest gate commit | Commit date | n |
| ----------- | -------- | --------------------------- | ------------------ | ----------- | - |
| (n/a) | | 20181220 | `04e56356520b98d5a93c496b10f02530bb6647e0` | 2018-12-17 | 17737 |
| 18.4.0 | 2019-01-21 | 20190117 | `f482e26cbeb654aaa01a12e3faae3878d6a59822` | 2019-01-15 | 17799 |
| 20.4.0 | 2021-01-11 | 20201217 | `3714f7be8e09c39a0ea7ce7ef44cb495ce250913` | 2020-12-16 | 20193 |
| 22.4.0 | 2023-01-10 | 20221229 | `f137b22e734e85642da3e56e8b94da3f5f027c73` | 2022-12-24 | 21425 |
| 24.4.1 | 2025-01-06 | 20241226 | `fdb843bd8379b0c0e3bc04ffbd7cbbb10776afc2` | 2024-12-19 | 22474 |
| 25.4.0 | 2026-01-09 | 20260108 | `29316b9c834da1aab0c095f56a69bd1e71121080` | 2026-01-05 | 22853 |

Adjacent platform images, for reference when adjusting a choice:

| Platform image | Newest gate commit | Commit date | n |
| -------------- | ------------------ | ----------- | - |
| 20210114 | `f73e1ebf60` | 2021-01-12 | 20236 |
| 20230112 | `20535e135f` | 2023-01-10 | 21441 |
| 20250109 | `80b758da23` | 2025-01-07 | 22498 |
| 20251211 | `8a52519630` | 2025-12-09 | 22839 |

Caveat: a user running `base-64-lts 24.4.1` is only *required* to be on
platform image 20220728 or newer. If the policy is to support the oldest
permissible platform image rather than the contemporary one, SmartOS becomes a
much tighter constraint. The precedent from `20181213-v1` is the contemporary
platform image, which is what the table above uses.

### OpenIndiana

ISO snapshots from <https://dlc.openindiana.org/isos/hipster/>.

| Snapshot | ISO date | Newest gate commit | Commit date | n | Source |
| -------- | -------- | ------------------ | ----------- | - | ------ |
| 2019.04 | 20190511 | `a547acf91a502e2d79ff67ef86d1b791883ca43a` | 2019-05-09 | 18398 | release notes |
| 2019.10 | 20191106 | `3423c61d20be9888e6633dfaeca21398c1f155cd` | 2019-11-05 | 19178 | computed |
| 2020.04 | 20200504 | `45de8795bcb0e4c49743f37edfdd2c89d5a7863b` | 2020-05-01 | 19662 | release notes |
| 2020.10 | 20201031 | `06524cf4e4f6c18e557fb244d42a8e47dba3b1b6` | 2020-10-29 | 20115 | release notes |
| 2021.04 | 20210430 | `e0cbdd5af707390adb289995fdf2dd8a3869dcca` | 2021-04-25 | 20473 | computed |
| 2021.10 | 20211031 | `79a6379db8` | 2021-10-30 | 20752 | computed |
| 2022.10 | 20221123 | `b8af4a8966ef2150997d7664836f5c360b849005` | 2022-11-21 | 21378 | computed |
| 2023.04 | 20230421 | `d27aea3ffc` | 2023-04-20 | 21595 | computed |
| 2023.10 | 20231027 | `67fa3f2c31` | 2023-10-26 | 21846 | computed |
| 2024.04 | 20240426 | `e0c5eaa00e` | 2024-04-26 | 22162 | computed |
| 2024.10 | 20241026 | `a8cd71ddc9` | 2024-10-24 | 22411 | computed |
| 20250402 | 20250402 | `3caf57556b91e230a55067f4d0d9c0f06992020d` | 2025-04-01 | 22626 | computed |
| 20251026 | 20251026 | `68259130da` | 2025-10-23 | 22810 | computed |
| 20260430 | 20260430 | `93d6c51de00648a982a50fbecc433b5482953fc7` | 2026-04-29 | 23026 | computed |

OI stopped publishing per-release notes after 2020.10; "computed" rows are gate
`master` as of the ISO date and may be off by a commit or two. For the three
rows where both sources exist they agree (2020.04, 2020.10 exactly; 2019.04
within one commit).

### Helios

Installer builds from <https://pkg.oxide.computer/install/>.
`latest-1.0` -> 20230520, `latest-2.0` -> 20251009, `latest-3.0` -> 20260509.

| Helios build | Series | stlouis commit | Newest upstream gate commit | Commit date | n |
| ------------ | ------ | -------------- | --------------------------- | ----------- | - |
| 20210826 | 1 | `0c21e24566` | `0c21e24566` | 2021-08-24 | - |
| 20211201 | 1 | `df07a22216` | `df07a22216` | 2021-11-30 | - |
| 20220616 | 1 | `eb76920a40` | `5c22bad5dc` | 2022-06-14 | - |
| 20230520 | 1 (last) | `87cd64a115` | `87cd64a11587dea20bafe125d7f26ca6e4b1a0e0` | 2023-05-19 | 21652 |
| 20230724 | 2 | `33e5c5d9e1` | `33e5c5d9e1` | 2023-07-24 | - |
| 20240506 | 2 | `e2a8479967` | `e2a8479967` | 2024-05-06 | - |
| 20241023 | 2 | `d378658631` | `d3786586313a5c55c1a903b178111c096d216365` | 2024-10-23 | 22409 |
| 20251009 | 2 (last) | `4751afd471` | `db46988bd1cacb6fe56bd23988729d129d4f94c6` | 2025-10-08 | 22791 |
| 20260509 | 3 | `83cfce2593` | `83cfce2593d5879e6831dd040afbd71e613d50f5` | 2026-05-09 | 23068 |

Helios 3 is based on OmniOS LTS r151054 userland (oxidecomputer/helios#244).

## Comparison with IPD 59

[IPD 59](https://github.com/illumos/ipd/blob/master/ipd/0059/README.adoc)
specifies a different, more conservative policy: for publication year `Y`, take
the most recent commit before 1 May of `Y - 3`. That rule produces:

| Publication year | Cutoff | Commit | Commit date | n | Tag | OmniOS LTS at commit |
| ---------------- | ------ | ------ | ----------- | - | --- | ------------------- |
| 2021 | 2018-05-01 | `6d1e6c904b` | 2018-04-30 | 17294 | | r151022 |
| 2022 | 2019-05-01 | `e742aada08` | 2019-04-30 | 18363 | | r151022 |
| 2023 | 2020-05-01 | `9f9cceb6f1` | 2020-04-30 | 19657 | | r151030 |
| 2024 | 2021-05-01 | `2ed5ea5a06df7f669d20d88729c625981a0de7bc` | 2021-04-30 | 20476 | `20210501-e0b4275f34-v0` | r151030 |
| 2025 | 2022-05-01 | `e0994bd28f025d3d74315f7479562b6be19773c3` | 2022-04-29 | 21056 | `20220429-e0994bd28f02-v1` | r151038 |
| 2026 | 2023-05-01 | `676abcb77c26296424298b37b96d2bce39ab25e5` | 2023-04-29 | 21609 | `20230429-676abcb77c26-v1` | r151038 |
| 2027 | 2024-05-01 | `72af5a458c3a` | 2024-04-30 | - | `20240430-72af5a458c3a-v1` | r151038 / r151046 |
| 2028 | 2025-05-01 | `7366ca9eaafd` | 2025-04-30 | - | `20250430-7366ca9eaafd-v1` | r151046 |
| 2029 | 2026-05-01 | `4648b9b8c36d` | 2026-04-30 | - | `20260430-4648b9b8c36d-v1` | r151054 |

The 2024 row is the base of the 20210501 prerelease (`env/illumos.20210501.sh`,
and the `sysroot/20210501` branch of illumos-gate). The prerelease tag uses the
`sysroot/20210501` branch head, `e0b4275f34`, which is one build backport on top
of the selected base commit. The 2025 row is the worked example in IPD 59
itself. Both agree with the computation above, which validates the method.

Two observations from that table:

* **There is a backlog.** IPD 59 was published 2026-01-27 and the 20210501
  prerelease is the *2024* artifact. The 2025 and 2026 artifacts
  (`20220429-e0994bd28f02` and `20230429-676abcb77c26`) are both still owed.
  Note also that the 20210501 prerelease names its files for the selected
  release date and the `sysroot/20210501` branch head rather than the base
  commit date/hash that IPD 59 would imply.
* **The 1 May cutoff always lands just before the new OmniOS LTS.** OmniOS
  releases LTS in early May, so "the LTS supported at the time of the commit"
  is always the *previous* one, roughly two years older than the commit. For
  the 2026 artifact that means r151038, whose gate is from 2021-03 and which
  ships only gcc 7 while the commit wants gcc 10. Building on r151046 instead
  (released two days after the commit, gate five weeks older, gcc 10) is far
  easier and is what `env/illumos.20230429.sh` does. Worth raising as an
  amendment: "the OmniOS LTS contemporary with the commit" would read better
  than "supported at the time of".

The adopted policy differs from this arithmetic by keying off actual support
windows instead of the calendar; for publication in 2026 it gives
`ae676b1204` (2023-12-26) rather than `676abcb77c26` (2023-04-29), about eight
months newer. The amendment to propose is therefore narrow: replace "the most
recent commit before 1 May of `Y - 3`" with "the newest commit present in both
the oldest supported OmniOS LTS and the oldest supported SmartOS pkgsrc LTS",
and replace "the OmniOS LTS version that was supported at the time of the
commit" with "the OmniOS LTS contemporary with the commit". The second change
matters on its own: because OmniOS ships LTS in early May and the cutoff is
1 May, the letter of the rule always names the *previous* LTS, roughly two
years older than the commit, and for anything from 2022 onwards that LTS has
only gcc 7 where the gate wants gcc 10.

## Open questions

* The SmartOS bound uses the platform image *contemporary* with the pkgsrc LTS
  release, following the precedent set by `20181213-v1`. A stricter reading
  would use the oldest platform image that LTS permits: `base-64-lts 24.4.1`
  only requires PI 20220728 or newer, which would drag the 2027 base back by
  two and a half years. This needs an explicit decision, since it is the single
  assumption the whole policy rests on.
* The pkgsrc LTS release dates are inferred from the pattern (Q4 release,
  published the following January) plus the confirmed 20.4.0 date of
  2021-01-11 and 24.4.1 date of 2025-01-06. Worth confirming the 23.4.x date
  with the pkgsrc folks before publishing, since it is what picks PI 20231228.
* Whether Helios should be a named target at all. It never binds under this
  policy, but stating support for it means committing to the fact that Helios
  releases track `stlouis`, which is not something the illumos project
  controls.
* aarch64: no distribution ships an illumos aarch64 release yet, so there is
  nothing to intersect. `omniosorg/illumos-omnios` has an `arm64-gate` branch
  to watch.
