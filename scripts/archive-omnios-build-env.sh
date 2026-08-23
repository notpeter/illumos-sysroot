#!/bin/sh
#
# Resolve the requested OmniOS build packages in a clean IPS image and preserve
# the exact package payload closure needed to replay that installation from
# local IPS archives.

set -eu

usage() {
	cat >&2 <<'EOF'
usage: scripts/archive-omnios-build-env.sh OUTDIR PACKAGE...

Environment:
  OMNIOS_CORE_SOURCE   core publisher source
                       (default: https://pkg.omnios.org/r151046/core)
  OMNIOS_EXTRA_SOURCE  extra publisher source
                       (default: https://pkg.omnios.org/r151046/extra)
  OMNIOS_ARCHIVE_WORKDIR
                       directory for temporary IPS images
                       (default: $TMPDIR or /tmp)
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

pkg_install_image() {
	image=$1
	shift

	set +e
	run_as_root pkg -R "$image" install --accept "$@"
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
	fmri_args=$(cat "$fmris")
	# shellcheck disable=SC2086
	pkgrecv -s "$source" -d "$archive" -a $fmri_args
	pkg list -f -g "$archive" > "$archive.list"
	# shellcheck disable=SC2086
	pkg contents -m -g "$archive" $fmri_args > "$archive.manifests"
	append_sha256 "$archive"
	append_sha256 "$archive.list"
	append_sha256 "$archive.manifests"
}

create_image() {
	image=$1
	core=$2
	extra=$3

	run_as_root rm -rf "$image"
	run_as_root pkg image-create -F -p "omnios=$core" "$image"
	run_as_root pkg -R "$image" set-publisher -g "$extra" extra.omnios
}

verify_archives() {
	image=$1
	core=$2
	extra=$3

	create_image "$image" "$core" "$extra"
	fmri_args=$(cat "$outdir/requested.fmris")
	# shellcheck disable=SC2086
	run_as_root pkg -R "$image" install -n --accept --no-refresh $fmri_args \
		> "$outdir/replay-verify.txt" 2>&1
	if grep -q 'Insufficient disk space' "$outdir/replay-verify.txt"; then
		cat "$outdir/replay-verify.txt" >&2
		return 1
	fi
	run_as_root rm -rf "$image"
	append_sha256 "$outdir/replay-verify.txt"
}

if [ "$#" -lt 2 ]; then
	usage
	exit 2
fi

outdir=$1
shift

core_source=${OMNIOS_CORE_SOURCE:-https://pkg.omnios.org/r151046/core}
extra_source=${OMNIOS_EXTRA_SOURCE:-https://pkg.omnios.org/r151046/extra}
workdir=${OMNIOS_ARCHIVE_WORKDIR:-${TMPDIR:-/tmp}}
scratch=$workdir/archive-omnios-build-env.$$
verify=$workdir/archive-omnios-build-env-verify.$$

trap 'run_as_root rm -rf "$scratch" "$verify"' EXIT HUP INT TERM

mkdir -p "$outdir"
mkdir -p "$workdir"
rm -f "$outdir/SHA256SUMS"

pkg list -Hv | awk '{ print $1 }' | sort > "$outdir/host-before.fmris"
pkg publisher -H > "$outdir/host-publishers.txt"

create_image "$scratch" "$core_source" "$extra_source"

printf '%s\n' "$@" > "$outdir/requested-packages.txt"
pkg_install_image "$scratch" "$@"

pkg -R "$scratch" list -Hv | awk '{ print $1 }' | sort \
	> "$outdir/install.fmris"
pkg -R "$scratch" publisher -H > "$outdir/scratch-publishers.txt"
pkg -R "$scratch" list -Hv "$@" | awk '{ print $1 }' | sort \
	> "$outdir/requested.fmris"

[ -s "$outdir/install.fmris" ] ||
	die "no package FMRIs selected for archive"

publisher_fmris omnios > "$outdir/omnios.fmris"
publisher_fmris extra.omnios > "$outdir/extra.omnios.fmris"

archive_publisher omnios "$core_source" "$outdir/omnios-r151046-core.p5p" \
	"$outdir/omnios.fmris"
archive_publisher extra.omnios "$extra_source" \
	"$outdir/omnios-r151046-extra.p5p" "$outdir/extra.omnios.fmris"

run_as_root rm -rf "$scratch"
verify_archives "$verify" "$outdir/omnios-r151046-core.p5p" \
	"$outdir/omnios-r151046-extra.p5p"

append_sha256 "$outdir/host-installed.fmris"
append_sha256 "$outdir/host-publishers.txt"
append_sha256 "$outdir/scratch-publishers.txt"
append_sha256 "$outdir/requested-packages.txt"
append_sha256 "$outdir/requested.fmris"
append_sha256 "$outdir/install.fmris"
append_sha256 "$outdir/host-before.fmris"
append_sha256 "$outdir/omnios.fmris"
append_sha256 "$outdir/extra.omnios.fmris"

printf 'archived build environment in %s\n' "$outdir"
