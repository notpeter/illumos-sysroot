#!/bin/sh
#
# Build illumos-gate twice and compare normalized repo.redist fingerprints.
# This is intended to run on an OmniOS builder with the same prerequisites as
# scripts/build-omnios-sysroot.sh.

set -eu

usage() {
	cat >&2 <<'EOF'
usage: scripts/check-repo-redist-repro.sh [options]

Options:
  -r RELEASE        sysroot profile release (default: 20231226)
  -w WORKDIR        working directory (default: $PWD/.sysroot-repo-repro)
  -o OUTDIR         comparison output directory (default: $PWD/output/repo-repro)
  -j JOBS           override DMAKE_MAX_JOBS for each nightly run
  -s                use the same absolute build path for both runs

By default, the script runs two clean build workdirs.  With -s, it runs both
builds under WORKDIR/build, deleting that directory between runs.  Each
resulting packages/i386/nightly-nd/repo.redist is fingerprinted, and diff
output is written under OUTDIR.  Package manifests and repository metadata
from each run are preserved under OUTDIR/RUN for exact content comparison.
EOF
}

die() {
	echo "ERROR: $*" >&2
	exit 1
}

release=20231226
workdir=
outdir=
jobs=
same_path=false

while getopts "r:w:o:j:sh" opt; do
	case "$opt" in
	r) release=$OPTARG ;;
	w) workdir=$OPTARG ;;
	o) outdir=$OPTARG ;;
	j) jobs=$OPTARG ;;
	s) same_path=true ;;
	h) usage; exit 0 ;;
	*) usage; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

[ "$#" -eq 0 ] || {
	usage
	exit 2
}

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
workdir=${workdir:-$repo_root/.sysroot-repo-repro}
outdir=${outdir:-$repo_root/output/repo-repro}

build_workdir() {
	run=$1

	if $same_path; then
		printf '%s\n' "$workdir/build"
	else
		printf '%s\n' "$workdir/$run"
	fi
}

run_build() {
	run=$1
	run_workdir=$(build_workdir "$run")
	run_output=$outdir/$run/archive

	if $same_path; then
		case "$run_workdir" in
		"$workdir"/build) rm -rf -- "$run_workdir" ;;
		*) die "refusing unsafe same-path workdir: $run_workdir" ;;
		esac
	else
		[ ! -e "$run_workdir" ] ||
			die "refusing to reuse existing build workdir: $run_workdir"
	fi
	[ ! -e "$run_output" ] ||
		die "refusing to reuse existing archive output: $run_output"

	mkdir -p "$run_output"

	set -- "$repo_root/scripts/build-omnios-sysroot.sh" \
		-r "$release" \
		-w "$run_workdir" \
		-o "$run_output"
	if [ -n "$jobs" ]; then
		set -- "$@" -j "$jobs"
	fi
	"$@"
}

fingerprint_run() {
	run=$1
	run_workdir=$(build_workdir "$run")
	repo=$run_workdir/illumos-gate/packages/i386/nightly-nd/repo.redist
	[ -d "$repo/file" ] && [ -d "$repo/pkg" ] ||
		die "missing repo.redist for $run: $repo"

	"$repo_root/scripts/fingerprint-repo-redist.sh" "$repo" \
		"$outdir/$run/repo-redist-fingerprint"

	pkg_capture=$outdir/$run/repo-redist-pkg
	[ ! -e "$pkg_capture" ] ||
		die "refusing to reuse package manifest capture: $pkg_capture"
	cp -R "$repo/pkg" "$pkg_capture"

	metadata_capture=$outdir/$run/repo-redist-metadata
	[ ! -e "$metadata_capture" ] ||
		die "refusing to reuse repository metadata capture: $metadata_capture"
	mkdir -p "$metadata_capture"
	for path in catalog index cfg_cache pkg5.repository; do
		[ ! -e "$repo/$path" ] || cp -R "$repo/$path" "$metadata_capture/"
	done
}

compare_file() {
	name=$1
	left=$outdir/run1/repo-redist-fingerprint/$name
	right=$outdir/run2/repo-redist-fingerprint/$name
	diffout=$outdir/$name.diff

	set +e
	diff -u "$left" "$right" > "$diffout"
	status=$?
	set -e
	if [ "$status" -ne 0 ]; then
		printf '%s differs: %s\n' "$name" "$diffout"
		return 1
	fi
	rm -f "$diffout"
}

archive_sha_file() {
	run=$1
	set -- "$outdir/$run/archive"/*.sha256
	[ "$#" -eq 1 ] && [ -f "$1" ] ||
		die "could not find exactly one archive checksum for $run"
	printf '%s\n' "$1"
}

compare_archive() {
	left=$(archive_sha_file run1)
	right=$(archive_sha_file run2)
	diffout=$outdir/archive.sha256.diff

	set +e
	diff -u "$left" "$right" > "$diffout"
	status=$?
	set -e
	if [ "$status" -ne 0 ]; then
		printf 'archive sha256 differs: %s\n' "$diffout"
		return 1
	fi
	rm -f "$diffout"
	printf 'archive sha256 matches: %s\n' "$left"
}

mkdir -p "$workdir" "$outdir"
workdir=$(CDPATH= cd -- "$workdir" && pwd)
outdir=$(CDPATH= cd -- "$outdir" && pwd)

run_build run1
fingerprint_run run1

run_build run2
fingerprint_run run2

failed=false
if ! compare_archive; then
	failed=true
fi
for name in paths.all paths.dirs paths.files paths.links files.sha256 \
	file-payloads.sha256 pkg-manifests.sha256 payload-actions.tsv; do
	if ! compare_file "$name"; then
		failed=true
	fi
done

if $failed; then
	die "repo.redist fingerprints differ; see $outdir"
fi

printf 'repo.redist fingerprints match: %s\n' "$outdir"
