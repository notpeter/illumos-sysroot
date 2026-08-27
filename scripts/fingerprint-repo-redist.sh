#!/bin/sh
#
# Write normalized fingerprints for an illumos repo.redist tree.

set -eu

awk_cmd=awk
if command -v nawk >/dev/null 2>&1; then
	awk_cmd=nawk
fi

usage() {
	cat >&2 <<'EOF'
usage: scripts/fingerprint-repo-redist.sh REPO_REDIST OUTDIR

REPO_REDIST must contain IPS file/ and pkg/ directories.  OUTDIR receives
stable path and checksum manifests suitable for diffing two repo.redist builds.
EOF
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

write_file_hashes() {
	prefix=$1
	output=$2
	paths=$output.paths.$$

	# IPS repository paths are generated hash/manifests paths and contain no
	# whitespace.  Batch them to avoid starting digest once per payload file.
	find "$prefix" -type f | LC_ALL=C sort | sed 's,^\./,,' > "$paths"
	if command -v digest >/dev/null 2>&1; then
		xargs -n 128 digest -a sha256 < "$paths" | "$awk_cmd" '
			/^\(.*\) = [0-9a-f]+$/ {
				path=$1
				sub(/^\(/, "", path)
				sub(/\)$/, "", path)
				print $3 "  " path
			}
		' > "$output"
	else
		xargs -n 128 sha256sum < "$paths" > "$output"
	fi
	rm -f "$paths"
}

write_payload_actions() {
	output=$1

	find ./pkg -type f | LC_ALL=C sort | while IFS= read -r manifest; do
		rel=${manifest#./}
		"$awk_cmd" -v manifest="$rel" '
			$1 == "file" {
				payload=$2
				path=""
				for (i = 3; i <= NF; i++) {
					if ($i ~ /^path=/) {
						path=substr($i, 6)
						break
					}
				}
				if (path != "") {
					printf "%s\t%s\t%s\t%s\n", path, manifest, payload, $0
				}
			}
		' "$manifest"
	done | LC_ALL=C sort > "$output"
}

if [ "$#" -ne 2 ]; then
	usage
	exit 2
fi

repo=$1
outdir=$2

[ -d "$repo/file" ] && [ -d "$repo/pkg" ] ||
	die "repo.redist must contain file/ and pkg/ directories: $repo"

mkdir -p "$outdir"
repo=$(CDPATH= cd -- "$repo" && pwd)
outdir=$(CDPATH= cd -- "$outdir" && pwd)

(
	cd "$repo"

	find . | LC_ALL=C sort | sed 's,^\./,,' > "$outdir/paths.all"
	find . -type d | LC_ALL=C sort | sed 's,^\./,,' > "$outdir/paths.dirs"
	find . -type f | LC_ALL=C sort | sed 's,^\./,,' > "$outdir/paths.files"
	find . -type l | LC_ALL=C sort | sed 's,^\./,,' > "$outdir/paths.links"

	write_file_hashes . "$outdir/files.sha256"
	write_file_hashes ./file "$outdir/file-payloads.sha256"
	write_file_hashes ./pkg "$outdir/pkg-manifests.sha256"
	write_payload_actions "$outdir/payload-actions.tsv"

	{
		printf 'repo=%s\n' "$repo"
		printf 'dirs=%s\n' "$(wc -l < "$outdir/paths.dirs" | tr -d ' ')"
		printf 'files=%s\n' "$(wc -l < "$outdir/paths.files" | tr -d ' ')"
		printf 'links=%s\n' "$(wc -l < "$outdir/paths.links" | tr -d ' ')"
		printf 'all-files-sha256=%s\n' \
			"$(sha256_file "$outdir/files.sha256")"
		printf 'file-payloads-sha256=%s\n' \
			"$(sha256_file "$outdir/file-payloads.sha256")"
		printf 'pkg-manifests-sha256=%s\n' \
			"$(sha256_file "$outdir/pkg-manifests.sha256")"
		printf 'payload-actions-sha256=%s\n' \
			"$(sha256_file "$outdir/payload-actions.tsv")"
	} > "$outdir/summary.txt"
)

printf 'fingerprint=%s\n' "$outdir"
