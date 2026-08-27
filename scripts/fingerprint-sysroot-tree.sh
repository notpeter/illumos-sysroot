#!/bin/sh
#
# Write normalized path, file, and symlink fingerprints for an extracted
# sysroot archive.

set -eu

awk_cmd=awk
if command -v nawk >/dev/null 2>&1; then
	awk_cmd=nawk
fi

usage() {
	echo "usage: scripts/fingerprint-sysroot-tree.sh TREE OUTDIR" >&2
}

die() {
	echo "ERROR: $*" >&2
	exit 1
}

sha256_file() {
	if command -v digest >/dev/null 2>&1; then
		digest -a sha256 "$1"
	else
		sha256sum "$1" | "$awk_cmd" '{ print $1 }'
	fi
}

[ "$#" -eq 2 ] || {
	usage
	exit 2
}

tree=$1
outdir=$2
[ -d "$tree" ] || die "missing tree: $tree"
mkdir -p "$outdir"
tree=$(CDPATH= cd -- "$tree" && pwd)
outdir=$(CDPATH= cd -- "$outdir" && pwd)

(
	cd "$tree"
	find . | LC_ALL=C sort | sed 's,^\./,,' > "$outdir/paths.all"
	find . -type d | LC_ALL=C sort | sed 's,^\./,,' > "$outdir/paths.dirs"
	find . -type f | LC_ALL=C sort | sed 's,^\./,,' > "$outdir/paths.files"
	find . -type l | LC_ALL=C sort | sed 's,^\./,,' > "$outdir/paths.links"

	find . -type f | LC_ALL=C sort | while IFS= read -r path; do
		rel=${path#./}
		printf '%s  %s\n' "$(sha256_file "$rel")" "$rel"
	done > "$outdir/files.sha256"

	find . -type l | LC_ALL=C sort | while IFS= read -r path; do
		rel=${path#./}
		printf '%s\t%s\n' "$rel" "$(readlink "$rel")"
	done > "$outdir/links.tsv"

	{
		printf 'tree=%s\n' "$tree"
		printf 'dirs=%s\n' "$(wc -l < "$outdir/paths.dirs" | tr -d ' ')"
		printf 'files=%s\n' "$(wc -l < "$outdir/paths.files" | tr -d ' ')"
		printf 'links=%s\n' "$(wc -l < "$outdir/paths.links" | tr -d ' ')"
		printf 'files-sha256=%s\n' "$(sha256_file "$outdir/files.sha256")"
		printf 'links-sha256=%s\n' "$(sha256_file "$outdir/links.tsv")"
	} > "$outdir/summary.txt"
)

printf 'fingerprint=%s\n' "$outdir"
