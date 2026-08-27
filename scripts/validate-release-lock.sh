#!/bin/sh
#
# Check that a checked-in release profile and its durable toolchain lock agree.
# This validates the trust anchors without downloading the large p5p payloads.

set -eu

awk_cmd=awk
if command -v nawk >/dev/null 2>&1; then
	awk_cmd=nawk
fi

usage() {
	echo "usage: scripts/validate-release-lock.sh RELEASE" >&2
}

die() {
	echo "ERROR: $*" >&2
	exit 1
}

if [ "$#" -ne 1 ]; then
	usage
	exit 2
fi

release=$1
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
profile=$repo_root/profiles/$release.mk
lock=$repo_root/locks/toolchain.$release.lock

[ -f "$profile" ] || die "unknown release profile: $release"
[ -f "$lock" ] || die "missing release lock: $lock"

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

lock_value() {
	key=$1
	"$awk_cmd" -F '\t' -v key="$key" \
		'$1 == key { print $2; exit }' "$lock"
}

check_equal() {
	label=$1
	expected=$2
	actual=$3
	[ -n "$expected" ] || die "$label is empty in profile"
	[ "$actual" = "$expected" ] ||
		die "$label mismatch: profile=$expected lock=$actual"
}

check_profile_field() {
	profile_key=$1
	lock_key=$2
	check_equal "$profile_key" "$(profile_value "$profile_key")" \
		"$(lock_value "$lock_key")"
}

[ "$(lock_value format)" = 1 ] || die "unsupported lock format"
[ "$(lock_value profile)" = "$release" ] || die "lock profile mismatch"

check_profile_field TARVERSION tarversion
check_profile_field BUILDER_RELEASE builder_release
check_profile_field BUILDER_IMAGE_URL builder_image_url
check_profile_field BUILDER_IMAGE_SHA256 builder_image_sha256
check_profile_field RELEASE_BASE_COMMIT release_base_commit
check_profile_field BUILD_HEAD_REF build_head_ref
check_profile_field BUILD_HEAD_COMMIT build_head_commit
check_profile_field SOURCE_DATE_EPOCH source_date_epoch
check_profile_field GATE_VERSION gate_version
check_profile_field GATE_COMPILER_NAME gate_compiler_name
check_profile_field GATE_CC gate_cc
check_profile_field GATE_CXX gate_cxx
check_profile_field SHIM_CC shim_cc
check_profile_field SHIM_LD shim_ld
check_profile_field SHIM_COMPILER_PACKAGE shim_compiler_package
check_profile_field SHIM_LINKER_PACKAGE shim_linker_package
check_profile_field GATE_LINT_MODE gate_lint_mode
check_profile_field GATE_COMPILER_PACKAGE gate_compiler_package
check_profile_field GATE_JDK_PACKAGE gate_jdk_package
check_profile_field GATE_JAVA_ROOT gate_java_root
check_profile_field MF2TAR_RUST_TOOLCHAIN mf2tar_rust_toolchain
check_profile_field MF2TAR_CARGO_LOCK_SHA256 mf2tar_cargo_lock_sha256
check_profile_field CLOSED_BINS_SHA256 closed_bins_sha256
check_profile_field CLOSED_BINS_ND_SHA256 closed_bins_nd_sha256

expected_gate_version=$(printf 'sysroot/%s-0-g%.12s' \
	"$release" "$(profile_value BUILD_HEAD_COMMIT)")
check_equal GATE_VERSION "$expected_gate_version" \
	"$(profile_value GATE_VERSION)"

closed_base=$(profile_value CLOSED_BINS_BASE_URL)
check_equal CLOSED_BINS_URL \
	"$closed_base/$(profile_value CLOSED_BINS_ARCHIVE)" \
	"$(lock_value closed_bins_url)"
check_equal CLOSED_BINS_ND_URL \
	"$closed_base/$(profile_value CLOSED_BINS_ND_ARCHIVE)" \
	"$(lock_value closed_bins_nd_url)"

profile_rejects=$(profile_value TOOLCHAIN_INSTALL_REJECTS)
lock_rejects=$("$awk_cmd" -F '\t' \
	'$1 == "install_reject" { printf "%s%s", separator, $2; separator=" " }' \
	"$lock")
[ "$profile_rejects" = "$lock_rejects" ] ||
	die "TOOLCHAIN_INSTALL_REJECTS mismatch: profile=$profile_rejects lock=$lock_rejects"

for package in \
	"$(profile_value SHIM_COMPILER_PACKAGE)" \
	"$(profile_value SHIM_LINKER_PACKAGE)"
do
	"$awk_cmd" -F '\t' -v package="$package" '
		$1 == "package_fmri" {
			name=$2
			sub(/^pkg:\/\/[^/]*\//, "", name)
			sub(/@.*/, "", name)
			if (name == package)
				found=1
		}
		END { exit !found }
	' "$lock" || die "package closure does not pin $package"
done

sha256_file() {
	if command -v digest >/dev/null 2>&1; then
		digest -a sha256 "$1"
	else
		sha256sum "$1" | "$awk_cmd" '{ print $1 }'
	fi
}

check_equal Cargo.lock \
	"$(profile_value MF2TAR_CARGO_LOCK_SHA256)" \
	"$(sha256_file "$repo_root/mf2tar/Cargo.lock")"

tmp_base=${TMPDIR:-/tmp}/illumos-sysroot-lock.$$
profile_packages=$tmp_base.profile
locked_packages=$tmp_base.lock
requested_fmris=$tmp_base.requested
package_fmris=$tmp_base.closure
trap 'rm -f "$profile_packages" "$locked_packages" "$requested_fmris" "$package_fmris"' \
	EXIT HUP INT TERM

gmake -s -C "$repo_root" print-gate-tool-packages RELEASE="$release" |
	LC_ALL=C sort > "$profile_packages"
"$awk_cmd" -F '\t' '$1 == "requested_fmri" {
	value=$2
	sub(/^pkg:\/\/[^/]*\//, "", value)
	sub(/@.*/, "", value)
	print value
}' "$lock" | LC_ALL=C sort > "$locked_packages"
diff -u "$profile_packages" "$locked_packages" ||
	die "requested packages differ from GATE_TOOL_PACKAGES"

"$awk_cmd" -F '\t' '$1 == "requested_fmri" { print $2 }' "$lock" \
	> "$requested_fmris"
"$awk_cmd" -F '\t' '$1 == "package_fmri" { print $2 }' "$lock" \
	> "$package_fmris"
[ -s "$requested_fmris" ] || die "lock has no requested package FMRIs"
[ -s "$package_fmris" ] || die "lock has no transitive package closure"
LC_ALL=C sort -c "$requested_fmris" || die "requested FMRIs are not sorted"
LC_ALL=C sort -c "$package_fmris" || die "package closure is not sorted"
if grep -Ei '(rust|cargo)' "$requested_fmris" >/dev/null; then
	die "gate-only requested toolchain contains Rust or Cargo"
fi

builder=$(profile_value BUILDER_RELEASE)
for artifact in \
	"omnios-$builder-core.p5p" \
	requested.fmris \
	install.fmris
do
	"$awk_cmd" -F '\t' -v artifact="$artifact" '
		$1 == "artifact_sha256" && $3 == artifact &&
		    length($2) == 64 && $2 !~ /[^0-9a-f]/ {
			found=1
		}
		END { exit !found }
	' "$lock" || die "lock has no valid hash for $artifact"
done

printf 'validated release profile and toolchain lock: %s\n' "$release"
