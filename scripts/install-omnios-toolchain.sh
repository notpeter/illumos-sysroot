#!/bin/sh
#
# Verify and install a profile's archived OmniOS gate toolchain without using a
# live IPS publisher.

set -eu

awk_cmd=awk
if command -v nawk >/dev/null 2>&1; then
	awk_cmd=nawk
fi

usage() {
	cat >&2 <<'EOF'
usage: scripts/install-omnios-toolchain.sh [-v] TOOLCHAIN_DIR

-v verifies the archives, requested packages, and exact installed runtime
closure without changing the image.

Set OMNIOS_TOOLCHAIN_CAPTURE_INSTALLED=1 while bootstrapping a new kit.  After
the exact requested packages are active, this replaces the empty-image solver
closure with the dependency closure selected on the pinned builder and
rewrites the kit lock.

Set OMNIOS_TOOLCHAIN_DENY_NEW_BE=1 only in a disposable VM that cannot reboot
between installation and use.  Normal persistent builders use a new boot
environment when IPS requires one.
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

lock_value() {
	key=$1
	"$awk_cmd" -F '\t' -v key="$key" \
		'$1 == key { print $2; exit }' "$lock"
}

verify_artifacts() {
	while read -r expected file; do
		[ -n "$expected" ] && [ -n "$file" ] ||
			die "malformed SHA256SUMS entry"
		[ -f "$toolchain_dir/$file" ] || die "missing locked artifact: $file"
		actual=$(sha256_file "$toolchain_dir/$file")
		[ "$actual" = "$expected" ] ||
			die "artifact checksum mismatch for $file: $actual"
	done < "$toolchain_dir/SHA256SUMS"
}

verify_checksum_manifest() {
	locked=/tmp/illumos-sysroot-artifacts-locked.$$
	supplied=/tmp/illumos-sysroot-artifacts-supplied.$$
	trap 'rm -f "$locked" "$supplied"' EXIT HUP INT TERM

	"$awk_cmd" -F '\t' \
		'$1 == "artifact_sha256" { print $2 "  " $3 }' \
		"$lock" | sort > "$locked"
	"$awk_cmd" -v lock="$(basename "$lock")" '$2 != lock { print }' \
		"$toolchain_dir/SHA256SUMS" | sort > "$supplied"
	[ -s "$locked" ] || die "toolchain lock has no artifact checksums"
	diff -u "$locked" "$supplied"
	rm -f "$locked" "$supplied"
	trap - EXIT HUP INT TERM
}

verify_exact_fmris() {
	root=$1
	expected=$2
	label=$3
	installed=/tmp/illumos-sysroot-toolchain-installed.$$
	trap 'rm -f "$installed"' EXIT HUP INT TERM

	[ -s "$expected" ] || die "empty $label FMRI set"
	toolchain_args=$(cat "$expected")
	set -- pkg
	if [ "$root" != / ]; then
		set -- "$@" -R "$root"
	fi
	# Exact FMRIs are used as patterns so an older or newer installed package
	# cannot satisfy the lock accidentally.
	# shellcheck disable=SC2086
	"$@" list -Hv $toolchain_args | "$awk_cmd" '{ print $1 }' | sort \
		> "$installed"
	diff -u "$expected" "$installed"
	rm -f "$installed"
	trap - EXIT HUP INT TERM
}

verify_installed_toolchain() {
	root=$1
	verify_exact_fmris "$root" "$toolchain_dir/requested.fmris" requested
	verify_exact_fmris "$root" "$toolchain_dir/install.fmris" closure

	set -- pkg
	if [ "$root" != / ]; then
		set -- "$@" -R "$root"
	fi
	install_rejects=$("$awk_cmd" -F '\t' \
		'$1 == "install_reject" { print $2 }' "$lock")
	for reject in $install_rejects; do
		if "$@" list -H "$reject" >/dev/null 2>&1; then
			die "lock-rejected package is still installed: $reject"
		fi
	done
}

capture_installed_lock() {
	repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
	OMNIOS_TOOLCHAIN_LOCK_ONLY=1 \
	OMNIOS_TOOLCHAIN_CAPTURE_INSTALLED=1 \
		"$repo_root/scripts/archive-omnios-build-env.sh" \
		-r "$profile" "$toolchain_dir"
}

image_root=/
verify_only=false

while getopts "R:vh" opt; do
	case "$opt" in
	R) image_root=$OPTARG ;;
	v) verify_only=true ;;
	h) usage; exit 0 ;;
	*) usage; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

[ "$#" -eq 1 ] || {
	usage
	exit 2
}

[ "$image_root" = / ] ||
	die "-R is not supported by builder-image runtime closure locks"

toolchain_dir=$1
[ -d "$toolchain_dir" ] || die "missing toolchain directory: $toolchain_dir"
toolchain_dir=$(CDPATH= cd -- "$toolchain_dir" && pwd)

set -- "$toolchain_dir"/toolchain.*.lock
[ "$#" -eq 1 ] && [ -f "$1" ] ||
	die "expected exactly one toolchain.*.lock in $toolchain_dir"
lock=$1

verify_checksum_manifest
verify_artifacts

format=$(lock_value format)
profile=$(lock_value profile)
builder_release=$(lock_value builder_release)
[ "$format" = 1 ] || die "unsupported toolchain lock format: $format"
[ -n "$profile" ] || die "toolchain lock has no profile"
[ -n "$builder_release" ] || die "toolchain lock has no builder release"

case "$(uname -v)" in
*"$builder_release"*) ;;
*) die "toolchain $profile requires OmniOS $builder_release; found $(uname -v)" ;;
esac

core=$toolchain_dir/omnios-$builder_release-core.p5p
extra=$toolchain_dir/omnios-$builder_release-extra.p5p
[ -s "$core" ] || die "missing core package archive: $core"
if [ ! -s "$extra" ]; then
	extra=
fi

fmri_args=$(cat "$toolchain_dir/requested.fmris")
[ -n "$fmri_args" ] || die "empty requested.fmris"

if $verify_only; then
	[ "$image_root" = / ] || die "-v cannot be combined with a non-root -R image"
	if [ "${OMNIOS_TOOLCHAIN_CAPTURE_INSTALLED:-}" = 1 ]; then
		capture_installed_lock
	fi
	verify_installed_toolchain /
	printf 'verified installed %s toolchain from %s\n' "$profile" "$toolchain_dir"
	exit 0
fi

if [ "$image_root" = / ]; then
	run_as_root pkg set-publisher -G '*' -M '*' omnios
	if pkg publisher extra.omnios >/dev/null 2>&1; then
		run_as_root pkg set-publisher -G '*' -M '*' extra.omnios
	fi
else
	[ ! -e "$image_root" ] || die "refusing existing image path: $image_root"
	run_as_root pkg image-create -F -p "omnios=$core" "$image_root"
	if [ -n "$extra" ]; then
		run_as_root pkg -R "$image_root" set-publisher -g "$extra" extra.omnios
	fi
fi

install_rejects=$("$awk_cmd" -F '\t' \
	'$1 == "install_reject" { print $2 }' "$lock")
for reject in $install_rejects; do
	set -- pkg
	if [ "$image_root" != / ]; then
		set -- "$@" -R "$image_root"
	fi
	if "$@" list -H "$reject" >/dev/null 2>&1; then
		installed_rejects="${installed_rejects:-} $reject"
	fi
done
set -- pkg
if [ "$image_root" != / ]; then
	set -- "$@" -R "$image_root"
fi
set -- "$@" install --accept --no-refresh
if [ "${OMNIOS_TOOLCHAIN_DENY_NEW_BE:-}" = 1 ]; then
	[ "$image_root" = / ] || die "OMNIOS_TOOLCHAIN_DENY_NEW_BE requires -R /"
	set -- "$@" --deny-new-be
fi
for reject in ${installed_rejects:-}; do
	set -- "$@" --reject "$reject"
done
set -- "$@" -g "$core"
if [ -n "$extra" ]; then
	set -- "$@" -g "$extra"
fi
# shellcheck disable=SC2086
set -- "$@" $fmri_args

set +e
run_as_root "$@"
status=$?
set -e
if [ "$status" -ne 0 ] && [ "$status" -ne 4 ]; then
	exit "$status"
fi

if [ "$image_root" = / ]; then
	if command -v beadm >/dev/null 2>&1; then
		pending_be=$(beadm list -H | "$awk_cmd" -F ';' '
			$3 ~ /R/ && $3 !~ /N/ { print $1; exit }
		')
		if [ -n "$pending_be" ]; then
			printf 'installed %s toolchain into pending boot environment %s\n' \
				"$profile" "$pending_be" >&2
			printf 'reboot, then run %s -v %s to verify the exact toolchain\n' \
				"$0" "$toolchain_dir" >&2
			exit 3
		fi
	fi
	if [ "${OMNIOS_TOOLCHAIN_CAPTURE_INSTALLED:-}" = 1 ]; then
		capture_installed_lock
	fi
	verify_installed_toolchain /
else
	pkg -R "$image_root" list -Hv | "$awk_cmd" '{ print $1 }' | sort \
		> "$image_root/.illumos-sysroot-installed.fmris"
	diff -u "$toolchain_dir/install.fmris" \
		"$image_root/.illumos-sysroot-installed.fmris"
fi

printf 'installed verified %s toolchain from %s\n' "$profile" "$toolchain_dir"
