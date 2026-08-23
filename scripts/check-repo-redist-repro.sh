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

The script runs two clean build workdirs, fingerprints each resulting
packages/i386/nightly-nd/repo.redist, and writes diff output under OUTDIR.
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

while getopts "r:w:o:j:h" opt; do
	case "$opt" in
	r) release=$OPTARG ;;
	w) workdir=$OPTARG ;;
	o) outdir=$OPTARG ;;
	j) jobs=$OPTARG ;;
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

run_build() {
	run=$1
	run_workdir=$workdir/$run
	run_output=$outdir/$run/archive

	[ ! -e "$run_workdir" ] ||
		die "refusing to reuse existing build workdir: $run_workdir"
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
	repo=$workdir/$run/illumos-gate/packages/i386/nightly-nd/repo.redist
	[ -d "$repo/file" ] && [ -d "$repo/pkg" ] ||
		die "missing repo.redist for $run: $repo"

	"$repo_root/scripts/fingerprint-repo-redist.sh" "$repo" \
		"$outdir/$run/repo-redist-fingerprint"
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

mkdir -p "$workdir" "$outdir"
workdir=$(CDPATH= cd -- "$workdir" && pwd)
outdir=$(CDPATH= cd -- "$outdir" && pwd)

run_build run1
fingerprint_run run1

run_build run2
fingerprint_run run2

failed=false
for name in paths.all paths.files files.sha256 file-payloads.sha256 pkg-manifests.sha256; do
	if ! compare_file "$name"; then
		failed=true
	fi
done

if $failed; then
	die "repo.redist fingerprints differ; see $outdir"
fi

printf 'repo.redist fingerprints match: %s\n' "$outdir"
