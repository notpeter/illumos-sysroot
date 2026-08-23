#!/bin/sh
#
# Extract the shim shared objects from an existing sysroot archive so a later
# repo.redist -> sysroot assembly can run on a host without the illumos linker.

set -eu

usage() {
	echo "usage: $0 SYSROOT_TAR_OR_TAR_GZ OUTDIR" >&2
}

if [ "$#" -ne 2 ]; then
	usage
	exit 2
fi

archive=$1
outdir=$2

case "$archive" in
*.tar.gz|*.tgz) compressed=true ;;
*.tar) compressed=false ;;
*) echo "ERROR: archive must end in .tar or .tar.gz" >&2; exit 2 ;;
esac

mkdir -p "$outdir"
if $compressed; then
	gzip -dc "$archive" | tar -xf - -C "$outdir" \
		usr/lib/libgcc_s.so.1 \
		usr/lib/amd64/libgcc_s.so.1 \
		usr/lib/libssp.so.0.0.0 \
		usr/lib/amd64/libssp.so.0.0.0
else
	tar -xf "$archive" -C "$outdir" \
		usr/lib/libgcc_s.so.1 \
		usr/lib/amd64/libgcc_s.so.1 \
		usr/lib/libssp.so.0.0.0 \
		usr/lib/amd64/libssp.so.0.0.0
fi

for shim in \
	"$outdir/usr/lib/libgcc_s.so.1" \
	"$outdir/usr/lib/amd64/libgcc_s.so.1" \
	"$outdir/usr/lib/libssp.so.0.0.0" \
	"$outdir/usr/lib/amd64/libssp.so.0.0.0"; do
	if [ ! -f "$shim" ]; then
		echo "ERROR: missing extracted shim: $shim" >&2
		exit 1
	fi
done

printf '%s\n' "$outdir"
