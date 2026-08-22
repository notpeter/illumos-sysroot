# Plan: publish an updated illumos sysroot

Self-contained handoff. Nothing in this document depends on prior
conversation.

## Why

The only published illumos sysroot is
[`20181213-de6af22ae73b-v1`](https://github.com/illumos/sysroot/releases/tag/20181213-de6af22ae73b-v1),
built from an illumos-gate commit dated 2018-12-13 and released 2020-04-12.
Rust's illumos CI still uses it. It is now the limiting factor for
[enabling zig to cross-compile to illumos](https://codeberg.org/ziglang/zig/issues/30971),
and for the .NET port (illumos/sysroot#3).

We want to publish a newer sysroot, and to leave behind tooling that can
produce the next one without re-deriving everything.

## Decisions already made

| Question | Decision |
| -------- | -------- |
| Base illumos-gate commit | `ae676b1204fb703d5b394f9f8d947ef6210f3c3f`, CommitDate 2023-12-26 ("16111 loader: Set twiddle globaldiv to 16 by default") |
| Release tag | `20231226-ae676b1204fb-v1` |
| Build host | OmniOS r151046 (LTS, released 2023-05-01) |
| Architecture | x86 only (`i386` + `amd64`), matching IPD 59 |
| Selection policy | Support-window variant of IPD 59: newest commit present in both the oldest supported OmniOS LTS and the oldest supported SmartOS pkgsrc LTS. Explicitly *not* IPD 59's fixed "before 1 May of `Y - 3`" arithmetic |
| Relationship to upstream | Build on the 20210501 prerelease/illumos/sysroot#5 line of work, do not fork away from it |
| Where the gate build runs | Peter's own OmniOS/Helios hardware, by hand, not in CI |

Rationale for the base commit and the policy, plus the per-distribution data
it was derived from, is in [`base-commit-candidates.md`](base-commit-candidates.md).
Short version: for publication in 2026 the oldest supported OmniOS LTS is
r151054 (gate 2025-04-11) and the oldest supported SmartOS pkgsrc LTS is
`base-64-lts` 23.4.x, whose contemporary platform image 20231228 carries gate
`ae676b1204` (2023-12-26). SmartOS binds. r151046 is chosen as the build host
because it is the OmniOS LTS contemporary with that commit *and* the oldest
LTS shipping gcc 10, which is what the gate wants as its primary compiler;
r151038 has only gcc 7.

## Background you will need

### What a sysroot archive is here

Headers and link-time shared libraries only, no runnable OS. It lets a
cross-compiler on Linux (or anywhere) target illumos via `--sysroot`. Contents
come from four or five IPS packages from a full illumos-gate build, minus
anything that is not a header or a library, plus two shim libraries.

### How the 2018 release was actually built

Two repositories:

1. **`illumos-gate` branch `sysroot/20181213`** -- the base commit plus five
   cherry-picked build-tool fixes (python3 in-gate tools, a `PYTHON_VERSION`
   regression, `nawk` cleanup, NULL fixes in `tic` and the iconv modules) so a
   December 2018 gate would compile on a newer host. There is also a
   `sysroot/20210501` branch carrying one build backport for the 20210501
   prerelease.
2. **`illumos/sysroot`** (this repository) -- `gmake archive`, which runs
   `mf2tar` against the IPS repository the gate build produced.

`mf2tar` is a small Rust tool in `mf2tar/`. It reads
`packages/$MACH/nightly-nd/repo.redist` directly, walks the manifests of the
requested packages, drops excluded paths, and splices in the shim libraries.
It builds clean on current rustc (verified on 1.97.1; warnings only).

The shims (`shims/libgcc_s`, `shims/libssp`) exist because `libgcc_s.so.1` and
`libssp.so.0.0.0` are present in `/usr/lib` on every illumos distribution but
come from the GCC consolidation, not illumos-gate. They are non-executable
stubs that export the right symbols at the right symbol versions. They are
linked with the **illumos** link-editor using `$mapfile_version 2` mapfiles,
so the archive step needs an illumos host too, not just the gate build.

### IPD 59

[IPD 59](https://github.com/illumos/ipd/blob/master/ipd/0059/README.adoc)
(published 2026-01-27) is the policy document. Read it. Its 8-step procedure is
what we are following, with two deviations we intend to propose as amendments:

1. **Commit selection.** IPD 59 says "for release year `Y`, the most recent
   commit before 1 May of `Y - 3`", which for 2026 gives `676abcb77c26`
   (2023-04-29). We use the support-window rule instead, giving `ae676b1204`
   (2023-12-26), about eight months newer. This matches IPD 59's own stated
   rationale ("the oldest supported LTS release from OmniOS, as well as the
   SmartOS LTS release against which illumos pkgsrc is built") rather than its
   arithmetic.
2. **Build host.** IPD 59 says "the OmniOS LTS version that was supported at
   the time of the commit". Because OmniOS ships LTS in early May and the
   cutoff is 1 May, that phrasing always names the *previous* LTS, roughly two
   years older than the commit, which from 2022 onwards means gcc 7 against a
   gate that wants gcc 10. We use the LTS *contemporary with* the commit.

Also note: **publishing is the Core Team's job** per IPD 59. We can prepare
and validate everything, but cutting the release is theirs.

And note the backlog. IPD 59 landed in January 2026, and the 20210501
prerelease is the artifact the policy assigns to publication year *2024*. The
2025 and 2026 artifacts have never been published. Whatever we do should be
framed as helping clear that, not as jumping the queue.

### Upstream state

* `illumos/sysroot` master has not moved since 2020-04-12.
* `gwr/sysroot` published prerelease
  [`20181213-de6af22ae73b-v2`](https://github.com/gwr/sysroot/releases/tag/20181213-de6af22ae73b-v2),
  which keeps the v1 base commit but adds `system/library/security/gss` so
  `libgss.so.1` is present in both `usr/lib` and `usr/lib/amd64`.
* `gwr/sysroot` published prerelease
  [`20210501-e0b4275f34-v0`](https://github.com/gwr/sysroot/releases/tag/20210501-e0b4275f34-v0),
  from illumos-gate branch `sysroot/20210501`. The branch head `e0b4275f34` is
  one build backport on top of the selected 2021-04-30 base commit
  `2ed5ea5a06df`.
* **PR #5** (pfmooney), branch `draft-20210501`: `env/illumos.20210501.sh`,
  README release notes, adds `system/library/security/gss` to
  `INCLUDE_PACKAGES`, and a commit titled "Release 20210501-v0" dated
  2026-05-27. Backed by `illumos-gate` branch `sysroot/20210501`.
* **PR #4** (gwr): just the libgss change, superseded by the v2 prerelease
  above and subsumed by #5.
* **Issue #3**: "New release", open since 2026-04-14, with the .NET port asking.
* **Issue #2**: sysroot lacks `sys/sdt.h`; jclulow declined as out of scope.
* Minor inconsistency worth mentioning upstream: the 20210501 prerelease names
  its files for the selected release date and backport branch head, while IPD
  59's convention and worked example use the base commit date/hash.

## State of this working tree

Branch `illumos_bump`. **Nothing is committed.** All of the following is
uncommitted working-tree change on top of `master` (which equals
`upstream/master`).

Added:

* `docs/base-commit-candidates.md` -- the selection policy, the per-distribution
  data it rests on, how to reproduce that data, and the comparison with IPD 59.
* `docs/plan.md` -- this file.
* `profiles/20181213.mk` -- reproduces the v2 prerelease contents, including
  `system/library/security/gss`.
* `profiles/20210501.mk` -- the 20210501 prerelease configuration, for
  reference.
* `profiles/20231226.mk` -- **the target of this work.**
* `env/illumos.20210501.sh` -- taken verbatim from PR #5.
* `env/illumos.20231226.sh` -- new. `usr/src/tools/env/illumos.sh` from
  `ae676b1204` verbatim, plus an appended block of r151046 overrides.

Modified:

* `Makefile` -- added `RELEASE=` profile selection (`profiles/*.mk`), turned
  the profile-overridable variables into `?=` assignments, threaded
  `LIBGCC_VERSION` through to the libgcc_s shim, and added an `ident` target
  that prints the vintage being built.
* `shims/libgcc_s/Makefile.com` -- added a `.version-$(VERSION)` stamp so that
  switching profiles rebuilds the shim instead of silently reusing objects
  built for a different set of symbol versions.
* `shims/libgcc_s/.gitignore` -- ignore the stamp.

**Unverified:** the Makefile's profile selection has never been run. `gmake
ident RELEASE=20231226` and `gmake ident RELEASE=bogus` are the first things to
try. GNU make is required (`?=`, `ifneq`, `$(wildcard)`, `$(error)`); there is
no `gmake` on the macOS box this was written on.

### The `env/illumos.20231226.sh` overrides, and why

Everything above the marker comment is the gate's own sample env file at
`ae676b1204`, verbatim. Appended after it:

| Override | Reason |
| -------- | ------ |
| `NIGHTLY_OPTIONS='-nCAmprt'` | Gate default is `-FnCDAmprt` (DEBUG only). The sysroot is assembled from `nightly-nd`, so we want non-DEBUG only. Halves the build. |
| `GNUC_ROOT=/opt/gcc-10`, `PRIMARY_CC`/`PRIMARY_CCC` | OmniOS puts gcc in `/opt/gcc-N`, not `/usr/gcc/N`. |
| `SHADOW_CCS=`, `SHADOW_CCCS=` | r151046 has no gcc 7. Clearing these *after* the sample file's smatch block also disables smatch, which we do not need and which is slow. |
| `PERL_VERSION=5.36`, `PERL_PKGVERS=`, `PERL_VARIANT=-thread-multi`, `BUILDPERL32='#'` | r151046 ships threaded 64-bit-only perl 5.36; the gate defaults to 5.10.0. |
| `PYTHON3_VERSION=3.11`, `PYTHON3_PKGVERS=-311`, `PYTHON3_SUFFIX=`, `TOOLS_PYTHON=` | r151046 ships python 3.11; the gate defaults to 3.9. |
| `JAVA_ROOT=/usr/jdk/openjdk11.0`, `JAVA_HOME`, `BLD_JAVA_11=` | r151046 ships OpenJDK 11, not 8. |

These were derived by diffing `usr/src/Makefile.master` at `ae676b1204`
against `usr/src/Makefile.master` on the `r151046` branch of
`omniosorg/illumos-omnios`. If the build fails on a tool version, that diff is
where to look first.

## Work remaining

### 1. Sanity-check the Makefile changes (minutes, any machine with GNU make)

```
gmake ident RELEASE=20231226      # should print commit, date, host, packages
gmake ident RELEASE=20181213      # should print the published release's config
gmake ident                       # should print "(none: custom build)"
gmake ident RELEASE=bogus         # should fail listing available profiles
gmake archive RELEASE=20231226    # should fail on missing ILLUMOS_PKGREPO
```

Note the `archive` recipe uses `[[ ]]`, which needs ksh93 or bash as `/bin/sh`.
That is pre-existing.

### 2. Build illumos-gate (hours, OmniOS r151046)

Provision r151046. Either a local VM or `vmactions/omnios-vm`, which has
images for r151046 through r151058 (`omnios-builder` would need extending for
anything older). Budget roughly 20-30 GB of disk.

Install the build prerequisites for that release: `pkg install
developer/build/onbld` gets most of it; also gcc 10, python 3.11, perl 5.36,
OpenJDK 11, and `illumos-tools` if r151046 provides it.

```
git clone https://github.com/illumos/illumos-gate
cd illumos-gate
git checkout ae676b1204fb703d5b394f9f8d947ef6210f3c3f
cp /path/to/sysroot/env/illumos.20231226.sh .
/opt/onbld/bin/nightly ./illumos.20231226.sh
```

Expect this to want iteration. `log/nightly.log` and `log/mail_msg` are where
the failures are. **Record every change you have to make**: env-file changes go
into `env/illumos.20231226.sh`, and anything that needs a source change becomes
a `sysroot/20231226` branch of illumos-gate (see the existing
`sysroot/20181213` and `sysroot/20210501` branches for the pattern) with
`GATE_BRANCH` in the profile updated to point at it. Prefer env-file changes;
source backports must not alter the exposed API or ABI, since that is the
entire point of the artifact.

This build is forward-looking (a 2023-12 gate on a 2023-05 host), which is the
easy direction. The backport branches that exist upstream were for the hard
direction, an old gate on a new host.

Success looks like `packages/i386/nightly-nd/repo.redist/cfg_cache` existing.

### 3. Assemble the archive (minutes, any illumos host)

```
gmake archive RELEASE=20231226 \
    ILLUMOS_PKGREPO=/path/to/illumos-gate/packages/i386/nightly-nd/repo.redist
```

Produces `output/illumos-sysroot-i386-20231226-ae676b1204fb-v1.tar.gz`.

Needs rust (for `mf2tar`), a C compiler, and the illumos link-editor (for the
shims). Can be a different machine from the gate build as long as the IPS
repository is reachable.

### 4. Decide the libgcc_s symbol version

`profiles/20231226.mk` sets `LIBGCC_VERSION = 4_8_0`, the same as the 2018
release, because advertising fewer symbol versions in the shim than the target
actually has is always safe. Every distribution this release targets ships a
`libgcc_s.so.1` from gcc 10 or newer, which should export `GCC_7.0.0`. Confirm
with

```
pvs -dsv /usr/lib/libgcc_s.so.1
```

on OmniOS r151054, a SmartOS PI 20231228-or-later host, current OpenIndiana,
and Helios. If `GCC_7.0.0` is present on all of them, bump to `7_0_0`; the only
symbol it adds is `__divmodti4`.

### 5. Verify the archive

* Spot-check: does it contain `usr/include`, `usr/lib/libc.so`,
  `usr/lib/amd64/libc.so`, the `libgcc_s`/`libssp` shims and their symlinks,
  and nothing from `usr/bin`, `etc`, `var`?
* `pvs -dsv` the shims out of the tarball and confirm the symbol versions are
  what the profile asked for.
* Cross-build something real from Linux against it. Rust is the established
  consumer; see
  [`illumos-toolchain.sh`](https://github.com/rust-lang/rust/blob/master/src/ci/docker/scripts/illumos-toolchain.sh)
  in the Rust tree for how that is wired up.
* Cross-build zig, which is the actual motivating consumer.
* Run one resulting binary on the *oldest* target: a SmartOS host on PI
  20231228 and an OmniOS r151054 host. This is the only test that actually
  validates the compatibility claim.

### 6. Wire up CI for the cheap half

Do not try to run the gate build in GitHub Actions: hosted runners give ~14 GB
on `/`, ~65 GB on `/mnt`, a 6-hour job cap, and 4 vCPUs under QEMU, against a
build that wants 20-30 GB and hours. Instead:

* Publish the `repo.redist` from step 2 once, as an artifact.
* CI the archive assembly (`shims` + `mf2tar` + tar/gzip) on every push using
  `vmactions/omnios-vm` with `release: r151046`. Minutes, and it is the part
  that actually benefits from regression testing.
* Optionally add a Linux job that cross-builds a hello-world against the
  resulting tarball.

### 7. Upstream it

* Comment on illumos/sysroot#3 with the plan and a pointer to
  `base-commit-candidates.md`.
* Propose the two IPD 59 amendments (commit selection, build host) as a
  concrete diff against `ipd/0059/README.adoc`.
* Offer the profile mechanism as a PR on top of #5, since #5's env file and
  the v2 libgss change are already carried here.
* The release itself has to be cut by the Core Team.

## Risks

* **The pkgsrc LTS date is inferred.** PI 20231228 was chosen because
  `base-64-lts` 23.4.x is believed to have shipped in January 2024, following
  the confirmed pattern of 20.4.0 on 2021-01-11 and 24.4.1 on 2025-01-06.
  Confirm before publishing; it is what picks the base commit.
* **The contemporary-PI assumption.** We assume someone running
  `base-64-lts` 23.4.x is on a platform image from around when that image
  shipped. The stricter reading is the oldest PI the LTS permits, and
  `base-64-lts` 24.4.1 only requires PI 20220728 or newer. Following the
  precedent of the 2018 release, whose notes cite platform images, we use the
  contemporary one. This is the load-bearing assumption of the whole policy.
* **The gate build will probably not work first time.** Budget for iteration
  and keep the env file and any backport branch as the record of what it took.
* **Deviating from IPD 59 without agreement** risks the Core Team declining to
  publish. Raise the amendments early rather than presenting a finished
  artifact.

## Useful commands

Reproducing the per-distribution data:

```
cd illumos-gate
git remote add omnios https://github.com/omniosorg/illumos-omnios
git remote add joyent https://github.com/TritonDataCenter/illumos-joyent
git remote add oxide  https://github.com/oxidecomputer/illumos-gate
git fetch --all

git merge-base origin/master omnios/r151046           # OmniOS LTS gate point
git merge-base origin/master joyent/release-20231228  # SmartOS PI gate point
git merge-base origin/master oxide/stlouis            # Helios gate point
git rev-list --count <commit>                         # ordering key; also
                                                      # OpenIndiana's package
                                                      # version suffix
```

`illumos-gate` `master` is effectively linear (two merge commits in ~23k), so
"newest commit common to all targets" is just the oldest of the per-target
merge-bases, and `rev-list --count` orders them.

OpenIndiana needs no fork: `oi-userland`'s
`components/openindiana/illumos-gate/Makefile` builds `illumos/illumos-gate`
`master` at `HEAD` daily, and sets `COMPONENT_REVISION` to
`git rev-list HEAD --count`, so a package version like
`system/kernel@0.5.11-2026.0.0.23228` names gate commit number 23228 exactly.
