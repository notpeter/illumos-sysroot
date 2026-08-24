#!/bin/sh
#
# Write normalized fingerprints for an illumos repo.redist tree.

set -eu

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
		sha256sum "$1" | awk '{ print $1 }'
	fi
}

write_file_hashes() {
	prefix=$1
	output=$2

	find "$prefix" -type f | LC_ALL=C sort | while IFS= read -r path; do
		rel=${path#./}
		sha=$(sha256_file "$rel")
		printf '%s  %s\n' "$sha" "$rel"
	done > "$output"
}

write_payload_actions() {
	output=$1

	find ./pkg -type f | LC_ALL=C sort | while IFS= read -r manifest; do
		rel=${manifest#./}
		awk -v manifest="$rel" '
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
