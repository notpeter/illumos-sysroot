# Reproducibility notes

This repository now has two separate build paths:

1. Archive assembly from an existing IPS repository.
2. The full illumos-gate build that produces the official `repo.redist`.

Only the first path has been validated so far.

## Archive assembly

The archive assembly path needs an illumos host with:

* `gmake`
* a C compiler and the illumos link-editor
* Rust and Cargo for `mf2tar`
* an IPS repository root containing `file/` and `pkg/`

The direct command is:

```sh
gmake archive RELEASE=20231226 \
    ILLUMOS_PKGREPO=/path/to/repository/publisher/root
```

`ILLUMOS_PKGREPO` should point at the directory that contains `file/` and
`pkg/`.  For a repository created with `pkgrecv`, that is usually
`$repo/publisher/$publisher`, not `$repo`.

For smoke testing against the packages installed in the current image:

```sh
repo=/tmp/sysroot-repo
pkgroot=$(RELEASE=20231226 scripts/receive-installed-packages.sh "$repo")
gmake archive RELEASE=20231226 ILLUMOS_PKGREPO="$pkgroot"
```

This proves the archive tooling, shims, profile selection, and package
manifest walk.  It does not prove that the archive contents correspond to the
selected 2023-12-26 illumos-gate commit unless the input repository came from
that gate build.

## Deterministic archive metadata

`mf2tar` writes ustar archive entries directly. For reproducible release
archives, it normalizes:

* tar entry uid/gid to `0`
* tar entry mtime to `SOURCE_DATE_EPOCH`
* gzip metadata with `gzip -n`

Each release profile sets `SOURCE_DATE_EPOCH` to the selected `GATE_COMMIT`
committer timestamp by default. The environment can still override it:

```sh
SOURCE_DATE_EPOCH=1703608857 gmake archive RELEASE=20231226 \
    ILLUMOS_PKGREPO=/path/to/repository/publisher/root
```

Custom builds without `SOURCE_DATE_EPOCH` continue to use the current time.
Archive member order is the deterministic manifest/package order emitted by
the selected IPS repository plus the explicitly listed shim entries.

## Validated smoke result

On 2026-08-21, this was validated on a Helios 3 VM at
`peter@192.168.122.29` using exact installed Helios package FMRIs:

```sh
RELEASE=20231226 scripts/receive-installed-packages.sh \
    /tmp/illumos-sysroot-20260821T201246Z/repo-script2
gmake archive RELEASE=20231226 \
    ILLUMOS_PKGREPO=/tmp/illumos-sysroot-20260821T201246Z/repo-script2/publisher/helios
```

Result:

* `output/illumos-sysroot-i386-20231226-ae676b1204fb-v1.tar.gz`
* size: 39.3 MiB
* contains `usr/include`
* contains the `libgcc_s` and `libssp` shim libraries for `i386` and `amd64`
* excludes `usr/bin`, `usr/sbin`, `usr/share`, `usr/ccs`, `etc`, `var`, `bin`,
  and `sbin`
* `pvs -dsv` shows the `libgcc_s` shims advertise `GCC_4.8.0`

Because the input packages were from Helios 3, this is a smoke artifact only.

## vmactions path

`.github/workflows/omnios-archive.yml` runs the same smoke assembly under
`vmactions/omnios-vm@027e3ec08fed6fb740ab5f300c2605f9de02997a`
(`v1.3.4`) with `release: r151046`.

The workflow uses the installed r151046 package FMRIs as input, so it is a CI
check for archive assembly.  It is not the official release build until it is
changed to consume a `repo.redist` produced from illumos-gate commit
`ae676b1204fb703d5b394f9f8d947ef6210f3c3f`.

For full illumos-gate builds, the workflow uses a two-stage OmniOS package
setup:

1. `build-env` boots OmniOS with live package access, installs the build
   packages, records the exact FMRIs installed, and preserves those payloads in
   `.p5p` IPS package archives.
2. `full-gate-build` downloads those package archives, removes live publisher
   origins from the VM image, installs the exact FMRIs from the local archives,
   and verifies the requested package FMRIs before building.

This keeps the release build from depending on live OmniOS package repositories
after the package archive artifact has been generated.

The archived payloads are the requested build packages plus packages that were
newly installed while preparing the matching vmactions base image.  They are
therefore sufficient to replay the build package installation on the same base
VM image without live package repositories.  They are not yet a complete
standalone dependency closure for installing the build environment into an
empty IPS image.

The package archive artifact includes:

* `omnios-r151046-core.p5p`
* `omnios-r151046-extra.p5p`
* `install.fmris`
* `requested.fmris`
* `changed.fmris`
* before/after installed package lists
* package archive package lists and manifests
* `SHA256SUMS`

This does not yet make the entire VM run offline.  The workflow still relies on
GitHub/vmactions to provide the VM image and source checkout, the builder still
fetches illumos-gate from Git, and `mf2tar` still uses Cargo normally.  Cargo
dependency vendoring is intentionally out of scope for now.  A future stronger
mode should preserve either the full installed image package set or a computed
cross-publisher dependency closure.

## Remaining official release work

To make `20231226-ae676b1204fb-v1` reproducible as an official sysroot:

1. Preserve the exact OmniOS package payloads needed for the build environment.
2. Build illumos-gate commit `ae676b1204fb703d5b394f9f8d947ef6210f3c3f` on
   OmniOS r151046 using `env/illumos.20231226.sh`.
3. Preserve the resulting
   `packages/i386/nightly-nd/repo.redist` or publish a reproducible way to
   fetch it.
4. Run `gmake archive RELEASE=20231226` against that `repo.redist`.
   The profile supplies `SOURCE_DATE_EPOCH=1703608857`.
5. Validate the archive by cross-building real consumers and running binaries
   on the oldest claimed targets.
