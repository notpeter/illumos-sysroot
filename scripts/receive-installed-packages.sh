#!/bin/sh
#
# Create a small local IPS repository from the exact package versions installed
# in the current image, and print the publisher root that mf2tar expects.

set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: RELEASE=yyyyMMdd $0 REPOSITORY_DIR" >&2
	exit 2
fi

repo=$1
release=${RELEASE:-}
pkg_source=${PKG_SOURCE:-}

if [ -z "$release" ]; then
	echo "ERROR: set RELEASE to the sysroot profile to receive" >&2
	exit 2
fi

packages=$(gmake -s print-packages RELEASE="$release")

if [ -z "$pkg_source" ]; then
	pkg_source=$(pkg publisher -H | awk '$3 == "online" { print $5; exit }')
fi

if [ -z "$pkg_source" ]; then
	echo "ERROR: set PKG_SOURCE or configure an online IPS publisher" >&2
	exit 1
fi

mkdir -p "$(dirname "$repo")"
pkgrepo create "$repo"

fmris=$(pkg list -Hv $packages | awk '{ print $1 }')
if [ -z "$fmris" ]; then
	echo "ERROR: no installed FMRIs found for profile packages" >&2
	exit 1
fi

# shellcheck disable=SC2086
pkgrecv -s "$pkg_source" -d "$repo" $fmris >&2
pkgrepo rebuild -s "$repo" >&2

publisher_root=$(find "$repo/publisher" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
if [ -z "$publisher_root" ] || [ ! -d "$publisher_root/file" ] ||
    [ ! -d "$publisher_root/pkg" ]; then
	echo "ERROR: could not find received publisher file/ and pkg/ directories" >&2
	exit 1
fi

printf '%s\n' "$publisher_root"
