# OmniOS toolchain locks

Each `toolchain.<DATE>.lock` is the checked-in trust anchor for one release.
It records the builder image, gate base and build head, fixed gate version,
compiler and JDK, closed bins, separate shim compiler/linker packages and
paths, assembly toolchain, exact requested package FMRIs, the transitive
IPS closure, and hashes for the external toolchain-kit artifacts.

Generate the package archives on OmniOS with:

```sh
scripts/archive-omnios-build-env.sh -r DATE OUTDIR
```

The archive script resolves the requested tools in an empty IPS image,
archives every package needed by that solver to p5p files, and proves that the
p5p files recreate the same empty-image result without a live publisher. That
scratch result is archive coverage; it is not forced onto a booted historical
image because its incorporation choices can differ from the pinned builder
baseline.

A bootable builder starts from the image URL and SHA-256 in the lock. While
bootstrapping a new lock, install the exact requested tools from the verified
p5p and capture the runtime dependency choices made on that image:

```sh
OMNIOS_TOOLCHAIN_CAPTURE_INSTALLED=1 \
    scripts/install-omnios-toolchain.sh OUTDIR
```

IPS can activate a new boot environment when incorporated base packages are
updated.  In that case the installer exits with status 3; reboot and run:

```sh
OMNIOS_TOOLCHAIN_CAPTURE_INSTALLED=1 \
    scripts/install-omnios-toolchain.sh -v OUTDIR
```

For a bootstrap that created a new boot environment, retain
`OMNIOS_TOOLCHAIN_CAPTURE_INSTALLED=1` on that post-reboot verification. The
capture writes the builder-selected closure to `install.fmris`, updates its
artifact hash, and rewrites `toolchain.DATE.lock`. Copy that lock into
`locks/`, then require a normal verification without the capture variable.

The installer always installs only `requested.fmris`. It then verifies every
exact requested FMRI and every exact runtime dependency in `install.fmris`.
Baseline packages can come from the content-pinned builder image; packages
added by the toolchain come from the verified p5p files. Acquisition-host
inventory, the empty-image replay set, and verbose transcripts remain evidence
but are not treated as the booted builder's package choices.

The p5p files are too large for this Git repository and must be preserved as
release inputs.  Regenerating a kit from a retained publisher is acceptable
only when its generated lock is byte-identical to the checked-in lock.

Builder-image incorporations remain in place and are themselves pinned by the
builder image digest. This avoids trying to replace a complete historical OS
with the newer incorporation selected by an empty scratch image.

Once finalized, regenerating the p5p artifacts can use the reviewed closure
from the checked lock and must reproduce the complete lock byte-for-byte:

```sh
OMNIOS_TOOLCHAIN_CLOSURE_LOCK="$PWD/locks/toolchain.DATE.lock" \
    scripts/archive-omnios-build-env.sh -r DATE OUTDIR
cmp locks/toolchain.DATE.lock OUTDIR/toolchain.DATE.lock
```

The lightweight CI check does not replace p5p replay.  It verifies that every
checked-in profile scalar, requested package name, reject entry, Cargo lock,
and external-artifact hash still agrees with its durable lock:

```sh
scripts/validate-release-lock.sh DATE
```
