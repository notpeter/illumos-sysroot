# Tools for illumos Sysroot Generation

A sysroot archive contains artefacts such as shared libraries and C header
files.  The archive contents can be used for cross compilation of binaries for
an illumos system on a foreign operating system such as Linux.  They can also
be used, with some care, to cross compile binaries for an earlier version of
illumos on a more current version.  Compilers generally have some way of
building against a set of headers and libraries other than the native shipped
compilation environment; e.g., GCC provides the `--sysroot` option.

## Official Sysroot Archives

At various times, the illumos project will make available official archives
with sysroot contents that can be used by other projects.  They will be
uploaded [to the GitHub release
page](https://github.com/illumos/sysroot/releases) for this repository.

Release files will have names of the form:
`illumos-sysroot-$MACH-$DATE-$COMMIT-$VERSION.tar.gz`.  For example,
`illumos-sysroot-i386-20181213-de6af22ae73b-v1.tar.gz` would be artefacts for
x86 machines (32- and 64-bit) built from `illumos-gate` commit
`de6af22ae73ba8d72672288621ff50b88f2cf5fd` which integrated on 13th
December, 2018.  The version number (e.g., `v1`) reflects the revision of the
contents as determined by the build process in this repository; we may choose
to add additional files to the sysroot, without moving to a newer base commit,
if requested by a consumer.

## Producing Archives

To build a sysroot archive, you need to build *illumos-gate* such that you get
a fully populate IPS repository; i.e., `packages/$MACH/nightly-nd/repo.redist`.
If you happen to have an existing IPS repository with sufficiently complete
contents, you may be able to use `pkgrecv` to download packages into a local
repository tree and use that instead, but this has not been tested.

Note that in order to build an older version of *illumos-gate* on a newer build
host, sometimes we have to backport a small number of fixes to the build tools.
We may also need to use a somewhat unusual environment file for `nightly`.
Care in backporting must be taken, so as to preserve the accuracy of the
exposed API and ABI in the headers and libraries in the sysroot archive.  The
backport lives in a branch of *illumos-gate* named for the base version date;
e.g.,
[sysroot/20181213](https://github.com/illumos/illumos-gate/tree/sysroot/20181213).
The environment file lives in this repository under `env/`.

You'll need to install Rust (to build `mf2tar`) and a C compiler (to build the
shims).  Once you have those, and you have your illumos packages, making the
archive is (hopefully!) as simple as:

```
$ gmake archive \
    ILLUMOS_PKGREPO=/ws/oldgate/packages/i386/nightly-nd/repo.redist
...
gzip < output/illumos-sysroot-i386-custom-v20200411-224313.tar > output/illumos-sysroot-i386-custom-v20200411-224313.tar.gz
```

Note that by default, the archive will be named with a custom version string to
make it easy to see that it is not an official release.  Release maintainers
must override the `TARVERSION` make variable appropriately.

## Release History

Detailed release notes are kept in [CHANGELOG.md](CHANGELOG.md).

| Release | Gate commit | Notable contents | Notes |
| ------- | ----------- | ---------------- | ----- |
| `20181213-de6af22ae73b-v2` | `de6af22ae73b` | Version 1 contents plus `libgss.so.1` from `system/library/security/gss` | [Changelog](CHANGELOG.md#sysroot-release-20181213-version-2) |
