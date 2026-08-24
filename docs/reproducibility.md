# Reproducibility notes

This repository now has three separate build paths:

1. Archive assembly from an existing IPS repository.
2. The full illumos-gate build that produces the official `repo.redist`.
3. Portable archive assembly from a fixed `repo.redist` plus prebuilt shim
   objects.

The first path is exercised by CI.  The third path has been validated locally by
assembling the same `repo.redist` and prebuilt shim inputs twice on Linux and
confirming byte-identical `.tar.gz` output.

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

## Portable archive assembly

The `repo.redist` to sysroot step does not inherently require illumos.  The
illumos-specific part is building the shim shared objects.  If those shim
objects are treated as fixed inputs, archive assembly can run on Linux or other
non-illumos hosts with Rust, Cargo, `gmake`, `gzip`, and `tar`.

Extract shim objects from an existing sysroot archive:

```sh
scripts/extract-prebuilt-shims.sh \
    output/illumos-sysroot-i386-20231226-ae676b1204fb-v1.tar.gz \
    /tmp/illumos-sysroot-shims
```

Assemble from a fixed `repo.redist`:

```sh
scripts/assemble-sysroot-from-repo.sh \
    /path/to/packages/i386/nightly-nd/repo.redist \
    /tmp/illumos-sysroot-shims
```

This runs:

```sh
gmake archive PREBUILT_SHIMS=true \
    PREBUILT_SHIM_DIR=/tmp/illumos-sysroot-shims \
    ILLUMOS_PKGREPO=/path/to/packages/i386/nightly-nd/repo.redist
```

The prebuilt shim directory must contain:

* `usr/lib/libgcc_s.so.1`
* `usr/lib/amd64/libgcc_s.so.1`
* `usr/lib/libssp.so.0.0.0`
* `usr/lib/amd64/libssp.so.0.0.0`

This makes it possible to reproduce the final sysroot archive from preserved
`repo.redist` and preserved shim inputs without booting an illumos builder.

Local validation from fixed inputs produced byte-identical archives across two
runs:

```text
c86cb4023396011f241e9b3b3598d9a66a38f53c43d13e7590a28be9736d5141  illumos-sysroot-i386-20231226-ae676b1204fb-v1.tar.gz
672713b70a2968e7f4379b1d148f0cb2d90c19125cda320c54d77a84f2634abd  decompressed tar stream
```

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

1. `build-env` boots OmniOS with live package access, creates a clean
   temporary IPS image, installs the build packages into that image, records
   that clean-image FMRI closure, and preserves those payloads in `.p5p` IPS
   package archives.
2. `full-gate-build` downloads those package archives, removes live publisher
   origins from the VM image, installs the exact requested build package FMRIs
   from the local archives, and verifies the requested package FMRIs before
   building.

This keeps the release build from depending on live OmniOS package repositories
after the package archive artifact has been generated.

The archived payloads are verified by creating another temporary IPS image and
dry-running an install of the exact requested package FMRIs using only the
generated package archives.  `install.fmris` records the full clean-image
closure available in those archives; `requested.fmris` records the exact build
package install targets used by the workflow.

The package archive artifact includes:

* `omnios-r151046-core.p5p`
* `omnios-r151046-extra.p5p`
* `install.fmris`
* `requested.fmris`
* `host-before.fmris`
* `scratch-publishers.txt`
* `replay-verify.txt`
* package archive package lists and manifests
* `SHA256SUMS`

This does not yet make the entire VM run offline.  The workflow still relies on
GitHub/vmactions to provide the VM image and source checkout, the builder still
fetches illumos-gate from Git, and `mf2tar` still uses Cargo normally.  Cargo
dependency vendoring is intentionally out of scope for now.

## `repo.redist` reproducibility checks

Use `scripts/check-repo-redist-repro.sh` to build illumos-gate twice and compare
normalized fingerprints of each resulting `repo.redist`:

```sh
scripts/check-repo-redist-repro.sh -r 20231226 -w /path/to/work -o /path/to/out -j 4
```

The comparison writes:

* `paths.all`
* `paths.files`
* `files.sha256`
* `file-payloads.sha256`
* `pkg-manifests.sha256`
* `payload-actions.tsv`
* one `.diff` file per mismatch

On 2026-08-23, two clean builds in different absolute work directories on the
local OmniOS r151046 VM both completed successfully, but the `repo.redist`
fingerprints differed:

```text
work: /home/peter/ws/repo-redist-repro-20260823T005422
out:  /home/peter/ws/repo-redist-repro-output-20260823T005422

run1 all-files-sha256:      9e66cf5abd100972226f63d14522b715125498a1b46caf3361240e7740984fcf
run2 all-files-sha256:      5da277ff6f167eee9f64e4071d0d26daa88874b3da48f20eb1359e78258b10e5
run1 file-payloads-sha256:  50e7d67a1f137272b0ba853f432093c27fb7fbe46f8a569e22f25c831f2625d6
run2 file-payloads-sha256:  766b680fff8b31a917b9bd02310cf2352aa641bf1cc69d6da68de96ce4540855
```

A sampled `libgss.so.1` payload embedded the absolute build directory path,
which explains some of that mismatch.

The same script supports `-s` to reuse one absolute build path and delete it
between runs:

```sh
scripts/check-repo-redist-repro.sh -s -r 20231226 -w /path/to/work -o /path/to/out -j 4
```

On the same VM, the same-path run also completed both builds successfully, but
`repo.redist` still differed:

```text
work: /home/peter/ws/repo-redist-repro-samepath-20260823T125413
out:  /home/peter/ws/repo-redist-repro-samepath-output-20260823T125413

run1 all-files-sha256:      4858dcc0d4537582aa1ea52139278b69e2137ce785da00421c54a4babcda8766
run2 all-files-sha256:      4a94db7ed0cffbe53da7f96abe8e481fd6e19a98a025bf51c8384e074c7390ec
run1 file-payloads-sha256:  3885021a10c9e3246a5e33e52e5a9e6cbce1bcf869286d3134bf17311126f7a6
run2 file-payloads-sha256:  2e3c96672a265538d18094a451cf96cffecb864580b575419f0ba62e3402b9bb
```

Extracting the two same-path sysroot archives showed identical symlink targets
but differing file contents.  The sysroot-relevant differences were narrowed to
`libc` outputs and `libssp_ns.a`, including:

* `lib/amd64/libc.so.1`
* `lib/libc.so.1`
* `usr/lib/libc/libc_hwcap*.so.1`
* `usr/lib/amd64/libssp_ns.a`
* `usr/lib/libssp_ns.a`

One `libc.so.1` difference is in generated DTrace symbol names such as
`$dtrace7375612.mutex_lock_impl` versus
`$dtrace7375146.mutex_lock_impl`.  So fixed absolute paths are not enough for
strict reproducibility.

A follow-up same-path run with fixed IPS publication timestamps and deterministic
`libssp_ns.a` archive creation still differed:

```text
work: /home/peter/ws/repo-redist-repro-patched-samepath-20260823T204200
out:  /home/peter/ws/repo-redist-repro-patched-samepath-output-20260823T204200

run1 archive sha256:        57d546dc9899dadac1ec2132c4687ea64722311cc30119932d59cb020f480987
run2 archive sha256:        b9f13a838748bfd1a291857d1fe82897eec8394f7ff351cb3b07fd49a8b1d953
run1 all-files-sha256:      c0888a612c119a59620e2ab7422761beeca29334e321454b827a69dd77cb7c1c
run2 all-files-sha256:      ad5b898f8213ff346e401853d126ceddd08664f2470c3a9ca226c7e481020c5d
run1 file-payloads-sha256:  5c1b79aa975ca59ad345bb2068b3d9532a7ac1c32dbd4eeb0872d6240f092e35
run2 file-payloads-sha256:  69383186dc59d204c9456e19e4a48043be104314da19f702dd35cfc1bc47cd53
run1 pkg-manifests-sha256:  2c101aec41444aab4c7054c05342803592986163ddc4eae57cd33ea2fafeac29
run2 pkg-manifests-sha256:  9b7482b52bc4a4bc901666b97cb26e1410bf5a2f90938b61c6816215a9a86744
```

For the sysroot archive itself, the remaining file-content differences were
only `libc` and its hwcap variants:

* `lib/amd64/libc.so.1`
* `lib/libc.so.1`
* `usr/lib/libc/libc_hwcap*.so.1`

`libssp_ns.a` no longer differed.  The remaining `libc` bytes were again only
the DTrace-generated `$dtraceNNNNNNN` symbol suffix.  Normalizing those suffixes
to a fixed seven-digit value made the two extracted `lib/libc.so.1` files
byte-identical in a targeted test.  `scripts/build-omnios-sysroot.sh` now
exports a `DTRACE` wrapper for nightly builds so host `dtrace -G` output objects
are normalized before they are linked.

A later same-path run with the `DTRACE` wrapper completed both gate builds and
produced byte-identical sysroot archives:

```text
work: /home/peter/ws/repo-redist-repro-dtracewrap3-samepath-20260823T233000
out:  /home/peter/ws/repo-redist-repro-dtracewrap3-samepath-output-20260823T233000

run1 archive sha256: e6c1493513788da5346e2cad1dd0ff59c27bce4fc60c9bd26b7576649feba334
run2 archive sha256: e6c1493513788da5346e2cad1dd0ff59c27bce4fc60c9bd26b7576649feba334
entries:             2629
```

The complete `repo.redist` still differed.  The remaining full-repository
differences included wall-clock catalog update names
(`catalog/update.20260823T23Z.C` versus `catalog/update.20260824T00Z.C`) and
manifest or payload differences in packages outside the archive's explicit
package set:

* `SUNWcs`
* `consolidation/osnet/osnet-message-files`
* `developer/build/onbld`
* `developer/dtrace`
* `library/libadt_jni`
* `service/network/slp`
* `service/resource-pools/poold`
* `system/dtrace/tests`

Follow-up payload action mapping narrowed the remaining content differences to
these classes:

* Java archives:
  * `usr/share/lib/slp/slpd.jar`
  * `usr/share/lib/slp/slp.jar`
  * `usr/share/lib/java/dtrace.jar`
  * `usr/lib/pool/JPool.jar`
  * `opt/SUNWdtrt/tst/common/java_api/test.jar`
  * `opt/SUNWdtrt/lib/java/jdtrace.jar`
  * `usr/lib/audit/Audit.jar`
* SMF seed repositories:
  * `lib/svc/seed/global.db`
  * `lib/svc/seed/nonglobal.db`
  * `usr/sadm/install/miniroot.db`
* Generated message file:
  * `usr/lib/locale/C/LC_MESSAGES/SUNW_OST_OSLIB.po`
* DTrace ustack test executables:
  * `opt/SUNWdtrt/tst/i386/ustack/tst.helper.exe`
  * `opt/SUNWdtrt/tst/i386/ustack/tst.annotated.exe`

The Java archive differences were confirmed to include build wall-clock ZIP
entry timestamps.  The OmniOS r151046 JDK `jar` does not support a `--date`
option, so `scripts/build-omnios-sysroot.sh` now creates a reproducible `jar`
wrapper when `SOURCE_DATE_EPOCH` is set and patches `usr/src/Makefile.master`
to use it.  The wrapper runs the real JDK `jar`, extracts the resulting
archive, sets all entry mtimes to `SOURCE_DATE_EPOCH`, and repacks with
`zip -X` in deterministic order.  It was smoke-tested on OmniOS for the legacy
`cf`, `cmf`, and `cfm` option forms used by illumos-gate and produced
byte-identical output across repeated runs.

A full same-path run with the `jar` wrapper initially exposed a wrapper bug:
the normalized archive was written under `/tmp`, and replacing a workspace JAR
could fail with `Cross-device link`.  The wrapper now creates its temporary
directory next to the target JAR before replacing it.

A follow-up same-path run with the fixed `jar` wrapper completed both gate
builds and produced byte-identical sysroot archives:

```text
work: /home/peter/ws/repo-redist-repro-jarwrap2-samepath-20260824T025128Z
out:  /home/peter/ws/repo-redist-repro-jarwrap2-samepath-output-20260824T025128Z

run1 archive sha256: 355223e8838ae8d26ba859f13066076b7a823b9dfde5132e47a56ded233a9310
run2 archive sha256: 355223e8838ae8d26ba859f13066076b7a823b9dfde5132e47a56ded233a9310
entries:             2629
```

The full `repo.redist` still differed.  Compared with the previous run, the
`jar` wrapper removed the `developer/dtrace`, `library/libadt_jni`,
`service/resource-pools/poold`, and most `system/dtrace/tests` Java archive
payload differences.  Remaining payload differences were:

* `lib/svc/seed/global.db`
* `lib/svc/seed/nonglobal.db`
* `usr/sadm/install/miniroot.db`
* `usr/lib/locale/C/LC_MESSAGES/SUNW_OST_OSLIB.po`
* `opt/SUNWdtrt/tst/i386/ustack/tst.helper.exe`
* `opt/SUNWdtrt/tst/i386/ustack/tst.annotated.exe`
* `usr/share/lib/slp/slp.jar`
* `usr/share/lib/slp/slpd.jar`

The remaining SLP JAR differences were traced to manifest content, not ZIP
entry metadata:

```text
Implementation-Version: [Mon Aug 24 03:45:16 UTC 2026]
```

The wrapper now also normalizes bracketed `Implementation-Version` timestamp
values to the `SOURCE_DATE_EPOCH` date string.  This was validated with a
targeted OmniOS wrapper test that produced byte-identical JARs from manifests
with different wall-clock `Implementation-Version` values.

A full same-path follow-up completed with the manifest normalization enabled:

```text
work: /home/peter/ws/repo-redist-repro-slpmanifest-samepath-20260824T042145Z
out:  /home/peter/ws/repo-redist-repro-slpmanifest-samepath-output-20260824T042145Z

run1 archive sha256: b9aaa56ae5b08f3b116d3361dd20ce662c75bd70176e56c793e77ee6b7b4c8b1
run2 archive sha256: b9aaa56ae5b08f3b116d3361dd20ce662c75bd70176e56c793e77ee6b7b4c8b1
entries:             2629
```

Both SLP JAR payloads matched in that run.  The remaining payload differences
were the three SQLite2 seed databases, the pyzfs message catalog, and the two
DTrace ustack test executables listed above.  Package manifest differences
remained in `SUNWcs`, `consolidation/osnet/osnet-message-files`,
`developer/build/onbld`, and `system/dtrace/tests`.  The comparison script now
preserves each run's complete `pkg/` manifest tree so future runs can show the
exact `developer/build/onbld` metadata difference instead of only its hash.

The remaining payload classes have now been traced and narrowly tested:

* The seed files are SQLite 2.1 databases.  Their schemas, table contents,
  rowids, and root pages matched even though their physical bytes did not.
  Directly replacing the four-byte schema cookie was insufficient, and even
  repeated `VACUUM` operations were nondeterministic with the stock native
  SQLite2 writer.  Reproducibility-only native SQLite changes now use a fixed
  random seed and zero raw allocations, freed page regions, and rounded cell
  padding.  A generated native tool runs `VACUUM` after each final seed update
  and writes the `SOURCE_DATE_EPOCH` as its schema cookie.  The tool compiled
  through the patched seed makefile and made all three preserved run1/run2
  database pairs byte-identical.
* `SUNW_OST_OSLIB.po` contained the same messages in a different order because
  `usr/src/lib/pyzfs/Makefile` passed unsorted `find` output to `xgettext`.
  Reproducibility mode now sorts that input under `LC_ALL=C`.
* Each ustack executable differed only in the low bytes of
  `DOF_SECT_ACTDESC.dofa_uarg`.  This is an in-process statement-descriptor
  pointer serialized into helper DOF by the host `dtrace -G`.  The DTrace
  wrapper now parses generated DOF and zeros only those eight-byte action
  fields.  Applying it to both preserved executable pairs made each pair
  byte-identical.
* Repository refresh used the wall clock for catalog update names and catalog
  attributes.  The generated `pkgrepo` wrapper pins Python `utcnow()` calls to
  `SOURCE_DATE_EPOCH`.  Refreshing two identical disposable repositories at
  different wall-clock times produced byte-identical trees.

A full same-path comparison completed with the SQLite, pyzfs, DTrace DOF, and
initial fixed-time catalog patch set:

```text
work: /home/peter/ws/repo-redist-repro-finalset-samepath-20260824T0845Z
out:  /home/peter/ws/repo-redist-repro-finalset-samepath-output-20260824T0845Z

run1 archive sha256: 6f5d144cc9add03072374081bf29e1817daacc4cd113594f08a60e77d8d93ee4
run2 archive sha256: 6f5d144cc9add03072374081bf29e1817daacc4cd113594f08a60e77d8d93ee4
entries:             2629
```

This eliminated every payload and package-manifest difference.  Repository
paths, content-addressed payloads, package manifests, and parsed file actions
all matched.  Only `catalog/catalog.attrs` and the search `index/` contents
differed.  The remaining causes were outside the initial `pkgrepo refresh`
wrapper:

* `pkgsend create-repository` recorded the wall clock in the catalog's
  `created` field.
* Search index generation used Python hash-based iteration with a randomized
  per-process hash seed, visibly changing `index/full_fmri_list` ordering and
  all dependent offset files.

Reproducibility mode now launches `pkgdepend`, `pkgsend`, and `pkgrepo` through
shell wrappers which set `PYTHONHASHSEED=0` before Python starts and run a
common fixed-datetime Python entry point.  All gate dependency generation,
dependency resolution, repository creation, publication, and refresh calls use
these wrappers.  Two repository creations separated by wall-clock time
produced byte-identical trees with `created=20231226T164057Z`.

The next full comparison exposed two narrower IPS ordering problems:

* `pkgdepend resolve` produced one `developer/build/onbld` `require-any`
  action with its two `fmri=` values in opposite orders.  The installed
  `pkgdepend` shebang uses Python's `-E` flag, so an exported
  `PYTHONHASHSEED` was ignored.  Invoking the script explicitly through the
  wrapper fixed this; two parallel resolutions of all 544 copied dependency
  manifests produced identical `developer-build-onbld.dep.res` files.
* Once every package manifest matched, only `index/fmri_offsets.v1`,
  `index/main_dict.ascii.v2`, and `index/manf_list.v1` differed.  IPS obtains
  the packages requiring indexing as a set, then assigns numeric manifest IDs
  in iteration order.  A fixed hash seed alone did not remove the influence of
  catalog and filesystem insertion order.  The `pkgrepo` entry point now sorts
  FMRIs by canonical string before the indexer assigns IDs.

Rebuilding repositories from the preserved run-1 and run-2 package trees with
the sorted-FMRI entry point produced byte-identical catalogs and indexes.  A
final clean same-path comparison then passed end to end:

```text
work: /home/peter/ws/repo-redist-repro-sortedfmri-samepath-20260824T1050Z
out:  /home/peter/ws/repo-redist-repro-sortedfmri-samepath-output-20260824T1050Z

run1 archive sha256: 75ba2e7a591e955f1e948a68334abe71b83ab779b84a21b6349774e2c174d130
run2 archive sha256: 75ba2e7a591e955f1e948a68334abe71b83ab779b84a21b6349774e2c174d130
entries:             2629
repo.redist:          all fingerprints match
```

The matching repository fingerprint covers 807 directories, 24,012 files,
all content-addressed payloads, package manifests, parsed file actions,
catalogs, and search indexes.

The archive package set was unchanged and did not appear in the differing
package manifest list:

* `system/header`
* `system/library`
* `system/library/math`
* `system/library/c-runtime`
* `system/library/security/gss`

So, as of this run, both the produced sysroot archive and the complete
`repo.redist` are byte-for-byte reproducible under the same absolute build path
and package environment.  This does not yet prove reproducibility across
different absolute paths, OmniOS package snapshots, or host environments.

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
