#!/bin/sh
#
# Install the requested OmniOS build packages and preserve the exact package
# payloads needed to replay that installation from local IPS archives.

set -eu

usage() {
	cat >&2 <<'EOF'
usage: scripts/archive-omnios-build-env.sh OUTDIR PACKAGE...

Environment:
  OMNIOS_CORE_SOURCE   core publisher source
                       (default: https://pkg.omnios.org/r151046/core)
  OMNIOS_EXTRA_SOURCE  extra publisher source
                       (default: https://pkg.omnios.org/r151046/extra)
EOF
}

die() {
	echo "ERROR: $*" >&2
	exit 1
}

run_as_root() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	elif command -v pfexec >/dev/null 2>&1; then
		pfexec "$@"
	else
		die "need root or pfexec for: $*"
	fi
}

sha256_file() {
	if command -v digest >/dev/null 2>&1; then
		digest -a sha256 "$1"
	else
		sha256sum "$1" | awk '{ print $1 }'
	fi
}

append_sha256() {
	file=$1
	sha=$(sha256_file "$file")
	printf '%s  %s\n' "$sha" "$(basename "$file")" >> "$outdir/SHA256SUMS"
}

pkg_install() {
	set +e
	run_as_root pkg install --accept "$@"
	status=$?
	set -e
	if [ "$status" -ne 0 ] && [ "$status" -ne 4 ]; then
		return "$status"
	fi
}

publisher_fmris() {
	publisher=$1
	awk -v publisher="$publisher" '
		index($0, "pkg://" publisher "/") == 1 { print }
	' "$outdir/install.fmris"
}

archive_publisher() {
	publisher=$1
	source=$2
	archive=$3
	fmris=$4

	if [ ! -s "$fmris" ]; then
		printf 'no %s packages to archive\n' "$publisher" >&2
		return
	fi

	rm -f "$archive"
	xargs pkgrecv -s "$source" -d "$archive" -a < "$fmris"
	pkg list -f -g "$archive" > "$archive.list"
	xargs pkg contents -m -g "$archive" < "$fmris" > "$archive.manifests"
	append_sha256 "$archive"
	append_sha256 "$archive.list"
	append_sha256 "$archive.manifests"
}

if [ "$#" -lt 2 ]; then
	usage
	exit 2
fi

outdir=$1
shift

core_source=${OMNIOS_CORE_SOURCE:-https://pkg.omnios.org/r151046/core}
extra_source=${OMNIOS_EXTRA_SOURCE:-https://pkg.omnios.org/r151046/extra}

mkdir -p "$outdir"
rm -f "$outdir/SHA256SUMS"

pkg list -Hv | sort > "$outdir/installed-before.fmris"
pkg publisher -H > "$outdir/publishers-before.txt"

run_as_root pkg set-publisher -G '*' -M '*' -g "$core_source" omnios
pkg publisher extra.omnios >/dev/null 2>&1 ||
	run_as_root pkg set-publisher -g "$extra_source" extra.omnios
run_as_root pkg refresh omnios extra.omnios

printf '%s\n' "$@" > "$outdir/requested-packages.txt"
pkg_install "$@"

pkg list -Hv | sort > "$outdir/installed-after.fmris"
pkg publisher -H > "$outdir/publishers-after.txt"
pkg list -Hv "$@" | awk '{ print $1 }' | sort > "$outdir/requested.fmris"

comm -13 "$outdir/installed-before.fmris" "$outdir/installed-after.fmris" \
	> "$outdir/changed.fmris"
cat "$outdir/requested.fmris" "$outdir/changed.fmris" |
	sort -u > "$outdir/install.fmris"

[ -s "$outdir/install.fmris" ] ||
	die "no package FMRIs selected for archive"

publisher_fmris omnios > "$outdir/omnios.fmris"
publisher_fmris extra.omnios > "$outdir/extra.omnios.fmris"

archive_publisher omnios "$core_source" "$outdir/omnios-r151046-core.p5p" \
	"$outdir/omnios.fmris"
archive_publisher extra.omnios "$extra_source" \
	"$outdir/omnios-r151046-extra.p5p" "$outdir/extra.omnios.fmris"

append_sha256 "$outdir/installed-before.fmris"
append_sha256 "$outdir/installed-after.fmris"
append_sha256 "$outdir/publishers-before.txt"
append_sha256 "$outdir/publishers-after.txt"
append_sha256 "$outdir/requested-packages.txt"
append_sha256 "$outdir/requested.fmris"
append_sha256 "$outdir/changed.fmris"
append_sha256 "$outdir/install.fmris"
append_sha256 "$outdir/omnios.fmris"
append_sha256 "$outdir/extra.omnios.fmris"

printf 'archived build environment in %s\n' "$outdir"
