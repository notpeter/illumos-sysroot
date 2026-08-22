# Changelog

## Versions

| Release | Gate commit | Summary |
| ------- | ----------- | ------- |
| [`20210501-e0b4275f34-v0`](#sysroot-release-20210501-version-0) | `e0b4275f34` | Prerelease from the `sysroot/20210501` branch; based on `2ed5ea5a06df` plus one build backport |
| [`20181213-de6af22ae73b-v2`](#sysroot-release-20181213-version-2) | `de6af22ae73b` | Version 1 contents plus `libgss.so.1` from `system/library/security/gss` |
| [`20181213-de6af22ae73b-v1`](#sysroot-release-20181213-version-1) | `de6af22ae73b` | Initial illumos sysroot release for x86, including headers, base libraries, and GCC shim libraries |

## Sysroot Release 20210501 Version 0

This is a prerelease from the `sysroot/20210501` illumos-gate branch:

```
commit e0b4275f346eda86b39157cd7dd3cc889a1f6988
Author:     Richard Lowe <richlowe@richlowe.net>
AuthorDate: Sat May 21 23:13:37 2022 +0000
Commit:     Patrick Mooney <pmooney@pfmooney.com>
CommitDate: Thu Nov 6 20:02:18 2025 +0000

    backport: 14710 remove long obsolete/unused pyzfs helper script
```

That branch head is based on:

```
commit 2ed5ea5a06df7f669d20d88729c625981a0de7bc
CommitDate: Fri Apr 30 07:14:42 2021 +0000

    13761 logadm: variable may be used uninitialized
```

The `e0b4275f34` backport removes obsolete `pyzfs` build/install references so
the 2021 gate can be built for sysroot production. The exposed headers and
link-time libraries remain anchored to the 2021 base commit.

The archive also includes `system/library/security/gss`, providing:

* `/usr/lib/{,amd64}/libgss.so.1`

## Sysroot Release 20181213 Version 2

Version 2 keeps the same illumos-gate commit and build tools as Version 1, but
adds `system/library/security/gss` for consumers that need GSS link-time
libraries:

* `/usr/lib/{,amd64}/libgss.so.1`

## Sysroot Release 20181213 Version 1

It is important to be deliberate with respect to what is included in the
sysroot archive. The contents affect the choice of target systems for which
binaries can be produced by the cross compiler.

In that spirit, this release uses the following illumos-gate commit:

```
commit de6af22ae73ba8d72672288621ff50b88f2cf5fd
Author:     Jason King <jason.brian.king@gmail.com>
AuthorDate: Thu Dec 13 10:43:17 2018 -0800
Commit:     Joshua M. Clulow <josh@sysmgr.org>
CommitDate: Thu Dec 13 10:43:17 2018 -0800

    9971 Make getrandom(2) a public interface
    Reviewed by: Dan McDonald <danmcd@joyent.com>
    Reviewed by: Mike Gerdts <mike.gerdts@joyent.com>
    Reviewed by: Peter Tribble <peter.tribble@gmail.com>
    Reviewed by: Robert Mustacchi <rm@joyent.com>
    Reviewed by: Andy Fiddaman <omnios@citrus-it.net>
    Reviewed by: Igor Kozhukhov <igor@dilos.org>
    Approved by: Joshua M. Clulow <josh@sysmgr.org>
```

This commit was available in:

* OpenIndiana in the [2019.04 ISO
  release](http://docs.openindiana.org/release-notes/2019.04-release-notes/),
  or via `pkg update` some time in December of 2018 if you had installed a
  prior release. Of note: packages from prior to 20190626 are sufficiently old
  at time of writing to have been garbage collected from the main IPS
  repository.
* SmartOS platform images starting with
  [20181220T002304Z](https://us-east.manta.joyent.com/Joyent_Dev/public/SmartOS/smartos.html#20181220T002304Z).
* OmniOS CE [releases](https://omniosce.org/schedule) starting with r151030
  (LTS, released 2019-05-06).

In addition to the illumos base, the archive includes these additional
libraries that appear in `/usr/lib` on all of the above platforms:

* `/usr/lib/{,amd64}/libssp.so.0.0.0` (version `LIBSSP_1.0`)
* `/usr/lib/{,amd64}/libgcc_s.so.1` (version `GCC_4.8.0`)

These additional GCC libraries are not usefully executable. They are shim
libraries that contain the same symbols and library versions as expected in the
real thing. This does not matter in practice, as the sysroot is for cross
compilation; the build machine must not execute program text for the target
machine. These shim libraries are created through mapfiles and stub code built
from this repository.
