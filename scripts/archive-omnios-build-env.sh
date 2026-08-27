#!/bin/sh
#
# Resolve the requested OmniOS build packages in a clean IPS image and preserve
# the exact package payload closure needed to replay that installation from
# local IPS archives.

set -eu

awk_cmd=awk
if command -v nawk >/dev/null 2>&1; then
	awk_cmd=nawk
fi

usage() {
	cat >&2 <<'EOF'
usage: scripts/archive-omnios-build-env.sh [-r RELEASE] OUTDIR [PACKAGE...]

When PACKAGE is omitted, the gate-only package set comes from the release
profile.  Rust and Cargo are intentionally excluded from that set.

Environment:
  OMNIOS_CORE_SOURCE   core publisher source
                       (default: https://pkg.omnios.org/$BUILDER_RELEASE/core)
  OMNIOS_EXTRA_SOURCE  extra publisher source
                       (default: https://pkg.omnios.org/$BUILDER_RELEASE/extra)
  OMNIOS_ARCHIVE_WORKDIR
                       directory for temporary IPS images
                       (default: $TMPDIR or /tmp)
  OMNIOS_TOOLCHAIN_LOCK_ONLY
                       rewrite the lock from existing evidence (default: unset)
  OMNIOS_TOOLCHAIN_CAPTURE_INSTALLED
                       replace the scratch closure with the exact dependency
                       closure on the current pinned builder (default: unset)
  OMNIOS_TOOLCHAIN_CLOSURE_LOCK
                       checked lock whose package_fmri set supplies a reviewed
                       builder closure (default: unset)
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
		sha256sum "$1" | "$awk_cmd" '{ print $1 }'
	fi
}

append_sha256() {
	file=$1
	sha=$(sha256_file "$file")
	printf '%s  %s\n' "$sha" "$(basename "$file")" >> "$outdir/SHA256SUMS"
}

replace_sha256() {
	file=$1
	base=$(basename "$file")
	"$awk_cmd" -v file="$base" '$2 != file { print }' \
		"$outdir/SHA256SUMS" > "$outdir/SHA256SUMS.new"
	mv "$outdir/SHA256SUMS.new" "$outdir/SHA256SUMS"
	append_sha256 "$file"
}

capture_installed_closure() {
	[ -s "$outdir/requested.fmris" ] ||
		die "missing requested.fmris for installed closure capture"
	closure=$outdir/install.fmris.new
	"$repo_root/scripts/capture-installed-package-closure.sh" \
		"$outdir/requested.fmris" "$closure"
	mv "$closure" "$outdir/install.fmris"
	replace_sha256 "$outdir/install.fmris"
}

use_locked_closure() {
	closure_lock=$1
	[ -s "$closure_lock" ] || die "missing closure lock: $closure_lock"
	"$awk_cmd" -F '\t' '$1 == "package_fmri" { print $2 }' \
		"$closure_lock" > "$outdir/install.fmris.new"
	[ -s "$outdir/install.fmris.new" ] ||
		die "closure lock has no package FMRIs: $closure_lock"
	mv "$outdir/install.fmris.new" "$outdir/install.fmris"
	replace_sha256 "$outdir/install.fmris"
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
	"$awk_cmd" -v publisher="$publisher" '
		index($0, "pkg://" publisher "/") == 1 { print }
	' "$outdir/install.fmris"
}

archive_publisher() {
	publisher=$1
	source=$2
	archive=$3
	fmris=$4

	if [ ! -s "$fmris" ]; then
		rm -f "$archive" "$archive.list" "$archive.manifests"
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

write_lock() {
	lock=$outdir/toolchain.$release.lock
	# Acquisition-host state and the verbose replay transcript are evidence,
	# not inputs.  Do not make the durable lock depend on either one.
	"$awk_cmd" -v file="$(basename "$lock")" '
		$2 != file &&
		$2 != "host-before.fmris" &&
		$2 != "host-publishers.txt" &&
		$2 != "replay-verify.txt" { print }
	' \
		"$outdir/SHA256SUMS" > "$outdir/SHA256SUMS.new"
	mv "$outdir/SHA256SUMS.new" "$outdir/SHA256SUMS"
	{
		printf 'format\t1\n'
		printf 'profile\t%s\n' "$release"
		printf 'tarversion\t%s\n' "$(profile_value TARVERSION)"
		printf 'builder_release\t%s\n' "$builder_release"
		printf 'builder_image_url\t%s\n' "$(profile_value BUILDER_IMAGE_URL)"
		printf 'builder_image_sha256\t%s\n' "$(profile_value BUILDER_IMAGE_SHA256)"
		printf 'core_source\t%s\n' "$core_source"
		printf 'extra_source\t%s\n' "$extra_source"
		printf 'gate_source\t%s\n' 'https://github.com/illumos/illumos-gate'
		printf 'release_base_commit\t%s\n' "$(profile_value RELEASE_BASE_COMMIT)"
		printf 'build_head_ref\t%s\n' "$(profile_value BUILD_HEAD_REF)"
		printf 'build_head_commit\t%s\n' "$(profile_value BUILD_HEAD_COMMIT)"
		printf 'source_date_epoch\t%s\n' "$(profile_value SOURCE_DATE_EPOCH)"
		printf 'gate_version\t%s\n' "$(profile_value GATE_VERSION)"
		printf 'gate_compiler_name\t%s\n' \
			"$(profile_value GATE_COMPILER_NAME)"
		printf 'gate_cc\t%s\n' "$(profile_value GATE_CC)"
		printf 'gate_cxx\t%s\n' "$(profile_value GATE_CXX)"
		printf 'shim_cc\t%s\n' "$(profile_value SHIM_CC)"
		printf 'shim_ld\t%s\n' "$(profile_value SHIM_LD)"
		printf 'shim_compiler_package\t%s\n' \
			"$(profile_value SHIM_COMPILER_PACKAGE)"
		printf 'shim_linker_package\t%s\n' \
			"$(profile_value SHIM_LINKER_PACKAGE)"
		printf 'gate_lint_mode\t%s\n' "$(profile_value GATE_LINT_MODE)"
		printf 'gate_compiler_package\t%s\n' \
			"$(profile_value GATE_COMPILER_PACKAGE)"
		printf 'gate_jdk_package\t%s\n' \
			"$(profile_value GATE_JDK_PACKAGE)"
		printf 'gate_java_root\t%s\n' "$(profile_value GATE_JAVA_ROOT)"
		printf 'mf2tar_rust_toolchain\t%s\n' \
			"$(profile_value MF2TAR_RUST_TOOLCHAIN)"
		printf 'mf2tar_cargo_lock_sha256\t%s\n' \
			"$(profile_value MF2TAR_CARGO_LOCK_SHA256)"
		printf 'closed_bins_url\t%s/%s\n' \
			"$(profile_value CLOSED_BINS_BASE_URL)" \
			"$(profile_value CLOSED_BINS_ARCHIVE)"
		printf 'closed_bins_sha256\t%s\n' "$(profile_value CLOSED_BINS_SHA256)"
		printf 'closed_bins_nd_url\t%s/%s\n' \
			"$(profile_value CLOSED_BINS_BASE_URL)" \
			"$(profile_value CLOSED_BINS_ND_ARCHIVE)"
		printf 'closed_bins_nd_sha256\t%s\n' \
			"$(profile_value CLOSED_BINS_ND_SHA256)"
		for reject in $(profile_value TOOLCHAIN_INSTALL_REJECTS); do
			printf 'install_reject\t%s\n' "$reject"
		done
		while IFS= read -r fmri; do
			printf 'requested_fmri\t%s\n' "$fmri"
		done < "$outdir/requested.fmris"
		while IFS= read -r fmri; do
			printf 'package_fmri\t%s\n' "$fmri"
		done < "$outdir/install.fmris"
		while read -r sha file; do
			printf 'artifact_sha256\t%s\t%s\n' "$sha" "$file"
		done < "$outdir/SHA256SUMS"
	} > "$lock"
	append_sha256 "$lock"
}

create_image() {
	image=$1
	core=$2
	extra=$3

	run_as_root rm -rf "$image"
	run_as_root pkg image-create -F -p "omnios=$core" "$image"
	if [ -n "$extra" ]; then
		run_as_root pkg -R "$image" set-publisher -g "$extra" extra.omnios
	fi
}

verify_archives() {
	image=$1
	core=$2
	extra=$3

	if [ ! -s "$extra" ]; then
		extra=
	fi
	create_image "$image" "$core" "$extra"
	fmri_args=$(cat "$outdir/requested.fmris")
	# shellcheck disable=SC2086
	set +e
	run_as_root pkg -R "$image" install --accept --no-refresh $fmri_args \
		> "$outdir/replay-verify.txt" 2>&1
	status=$?
	set -e
	if [ "$status" -ne 0 ] && [ "$status" -ne 4 ]; then
		cat "$outdir/replay-verify.txt" >&2
		return "$status"
	fi
	if grep -q 'Insufficient disk space' "$outdir/replay-verify.txt"; then
		cat "$outdir/replay-verify.txt" >&2
		return 1
	fi
	pkg -R "$image" list -Hv | "$awk_cmd" '{ print $1 }' | sort \
		> "$outdir/replay.fmris"
	diff -u "$outdir/install.fmris" "$outdir/replay.fmris" \
		> "$outdir/replay.fmris.diff" || {
		cat "$outdir/replay.fmris.diff" >&2
		return 1
	}
	rm -f "$outdir/replay.fmris.diff"
	run_as_root rm -rf "$image"
	append_sha256 "$outdir/replay.fmris"
}

release=20231226

while getopts "r:h" opt; do
	case "$opt" in
	r) release=$OPTARG ;;
	h) usage; exit 0 ;;
	*) usage; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

if [ "$#" -lt 1 ]; then
	usage
	exit 2
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
profile=$repo_root/profiles/$release.mk
[ -f "$profile" ] || die "unknown release profile: $release"

profile_value() {
	key=$1
	"$awk_cmd" -v key="$key" '
		$1 == key {
			value=$0
			equals=index(value, "=")
			if (equals == 0)
				exit
			value=substr(value, equals + 1)
			tab=sprintf("%c", 9)
			while (substr(value, 1, 1) == " " ||
			    substr(value, 1, 1) == tab)
				value=substr(value, 2)
			print value
			exit
		}
	' "$profile"
}

outdir=$1
shift

builder_release=$(profile_value BUILDER_RELEASE)
[ -n "$builder_release" ] || die "missing BUILDER_RELEASE in $profile"
core_source=${OMNIOS_CORE_SOURCE:-https://pkg.omnios.org/$builder_release/core}
extra_source=${OMNIOS_EXTRA_SOURCE:-https://pkg.omnios.org/$builder_release/extra}
workdir=${OMNIOS_ARCHIVE_WORKDIR:-${TMPDIR:-/tmp}}
scratch=$workdir/archive-omnios-build-env.$$
verify=$workdir/archive-omnios-build-env-verify.$$

if [ "$#" -eq 0 ]; then
	set -- $(gmake -s -C "$repo_root" print-gate-tool-packages RELEASE="$release")
fi

trap 'run_as_root rm -rf "$scratch" "$verify"' EXIT HUP INT TERM

mkdir -p "$outdir"
mkdir -p "$workdir"
[ -z "${OMNIOS_TOOLCHAIN_CAPTURE_INSTALLED:-}" ] ||
	[ -z "${OMNIOS_TOOLCHAIN_CLOSURE_LOCK:-}" ] ||
	die "choose only one installed or checked-lock closure source"
if [ "${OMNIOS_TOOLCHAIN_LOCK_ONLY:-}" = 1 ]; then
	[ -s "$outdir/SHA256SUMS" ] || die "missing existing SHA256SUMS in $outdir"
	if [ "${OMNIOS_TOOLCHAIN_CAPTURE_INSTALLED:-}" = 1 ]; then
		capture_installed_closure
	elif [ -n "${OMNIOS_TOOLCHAIN_CLOSURE_LOCK:-}" ]; then
		use_locked_closure "$OMNIOS_TOOLCHAIN_CLOSURE_LOCK"
	fi
	write_lock
	printf 'rewrote %s toolchain lock in %s\n' "$release" "$outdir"
	exit 0
fi
rm -f "$outdir/SHA256SUMS"

pkg list -Hv | "$awk_cmd" '{ print $1 }' | sort > "$outdir/host-before.fmris"
pkg publisher -H > "$outdir/host-publishers.txt"

create_image "$scratch" "$core_source" "$extra_source"

printf '%s\n' "$@" > "$outdir/requested-packages.txt"
pkg_install_image "$scratch" "$@"

pkg -R "$scratch" list -Hv | "$awk_cmd" '{ print $1 }' | sort \
	> "$outdir/install.fmris"
pkg -R "$scratch" publisher -H > "$outdir/scratch-publishers.txt"
pkg -R "$scratch" list -Hv "$@" | "$awk_cmd" '{ print $1 }' | sort \
	> "$outdir/requested.fmris"

[ -s "$outdir/install.fmris" ] ||
	die "no package FMRIs selected for archive"

publisher_fmris omnios > "$outdir/omnios.fmris"
publisher_fmris extra.omnios > "$outdir/extra.omnios.fmris"

archive_publisher omnios "$core_source" \
	"$outdir/omnios-$builder_release-core.p5p" \
	"$outdir/omnios.fmris"
archive_publisher extra.omnios "$extra_source" \
	"$outdir/omnios-$builder_release-extra.p5p" "$outdir/extra.omnios.fmris"

run_as_root rm -rf "$scratch"
verify_archives "$verify" "$outdir/omnios-$builder_release-core.p5p" \
	"$outdir/omnios-$builder_release-extra.p5p"

append_sha256 "$outdir/scratch-publishers.txt"
append_sha256 "$outdir/requested-packages.txt"
append_sha256 "$outdir/requested.fmris"
append_sha256 "$outdir/install.fmris"
append_sha256 "$outdir/omnios.fmris"
append_sha256 "$outdir/extra.omnios.fmris"
if [ "${OMNIOS_TOOLCHAIN_CAPTURE_INSTALLED:-}" = 1 ]; then
	capture_installed_closure
elif [ -n "${OMNIOS_TOOLCHAIN_CLOSURE_LOCK:-}" ]; then
	use_locked_closure "$OMNIOS_TOOLCHAIN_CLOSURE_LOCK"
fi
write_lock

printf 'archived %s build environment in %s\n' "$release" "$outdir"
