#!/bin/sh
#
# Assemble a sysroot archive from an existing repo.redist using prebuilt shim
# objects.  This path is intended to work on non-illumos hosts.

set -eu

usage() {
	cat >&2 <<'EOF'
usage: scripts/assemble-sysroot-from-repo.sh [options] REPO_REDIST PREBUILT_SHIM_DIR

Options:
  -r RELEASE        sysroot profile release (default: 20231226)
  -o OUTPUT         output directory (default: $PWD/output)

PREBUILT_SHIM_DIR must contain:
  usr/lib/libgcc_s.so.1
  usr/lib/amd64/libgcc_s.so.1
  usr/lib/libssp.so.0.0.0
  usr/lib/amd64/libssp.so.0.0.0
EOF
}

release=20231226
output=

while getopts "r:o:h" opt; do
	case "$opt" in
	r) release=$OPTARG ;;
	o) output=$OPTARG ;;
	h) usage; exit 0 ;;
	*) usage; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

if [ "$#" -ne 2 ]; then
	usage
	exit 2
fi

repo=$1
shim_dir=$2
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output=${output:-$repo_root/output}

cd "$repo_root"
gmake archive \
	RELEASE="$release" \
	OUTPUT="$output" \
	ILLUMOS_PKGREPO="$repo" \
	PREBUILT_SHIMS=true \
	PREBUILT_SHIM_DIR="$shim_dir"
