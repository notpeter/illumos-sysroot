#!/bin/sh
#
# Build an illumos-gate IPS repo on OmniOS and assemble the sysroot archive
# from it.  This script is intended to run inside an OmniOS host or
# vmactions/omnios-vm.

set -eu
export LC_ALL=C
export LANG=C

awk_cmd=awk
if command -v nawk >/dev/null 2>&1; then
	awk_cmd=nawk
fi

usage() {
	cat >&2 <<'EOF'
usage: scripts/build-omnios-sysroot.sh [options]

Options:
  -r RELEASE        sysroot profile release (default: 20231226)
  -w WORKDIR        working directory (default: $PWD/.sysroot-omnios)
  -g GATE_DIR       illumos-gate checkout path (default: $WORKDIR/illumos-gate)
  -o OUTPUT         archive output directory (default: $PWD/output)
  -j JOBS           override DMAKE_MAX_JOBS in the copied nightly env
  -i                install OmniOS build dependencies first

Environment:
  GATE_REPO         illumos-gate remote (default: https://github.com/illumos/illumos-gate)
  GATE_BUILD_COMMIT illumos-gate build head; defaults from profiles/$RELEASE.mk
  GATE_BRANCH       local checkout branch name (default: sysroot/$RELEASE)
  GATE_CC           override the profile C compiler path
  GATE_CXX          override the profile C++ compiler path
  CLOSED_BINS_CACHE directory for verified closed-bins downloads
                     (default: $WORKDIR/inputs)
  TMPDIR             nightly temporary directory
                     (default: $WORKDIR/tmp)
  OMNIOS_TOOLCHAIN_DIR
                     verified per-profile toolchain archive directory
  ILLUMOS_SYSROOT_REQUIRE_LOCKED_TOOLCHAIN
                     fail unless OMNIOS_TOOLCHAIN_DIR is set (default: unset)
  SOURCE_DATE_EPOCH reproducible build timestamp; defaults from profiles/$RELEASE.mk
  ILLUMOS_SYSROOT_ALLOW_BUILDER_MISMATCH
                     allow source-preparation diagnostics on another OmniOS release
                     (default: unset)
  ILLUMOS_SYSROOT_PREPARE_ONLY
                     stop after preparing and patching the gate (default: unset)
  ILLUMOS_SYSROOT_GATE_ONLY
                     stop after building and validating repo.redist (default: unset)
EOF
}

die() {
	echo "ERROR: $*" >&2
	exit 1
}

release=20231226
workdir=
gate_dir=
output=
jobs=
install_deps=false

while getopts "r:w:g:o:j:ih" opt; do
	case "$opt" in
	r) release=$OPTARG ;;
	w) workdir=$OPTARG ;;
	g) gate_dir=$OPTARG ;;
	o) output=$OPTARG ;;
	j) jobs=$OPTARG ;;
	i) install_deps=true ;;
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
profile=$repo_root/profiles/$release.mk
env_file=$repo_root/env/illumos.$release.sh

[ -f "$profile" ] || die "unknown release profile: $release"
[ -f "$env_file" ] || die "missing nightly env file: $env_file"

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

workdir=${workdir:-$repo_root/.sysroot-omnios}
gate_dir=${gate_dir:-$workdir/illumos-gate}
output=${output:-$repo_root/output}
gate_repo=${GATE_REPO:-https://github.com/illumos/illumos-gate}
release_base_commit=$(profile_value RELEASE_BASE_COMMIT)
profile_build_commit=$(profile_value BUILD_HEAD_COMMIT)
gate_commit=${GATE_BUILD_COMMIT:-${GATE_COMMIT:-$profile_build_commit}}
build_head_ref=$(profile_value BUILD_HEAD_REF)
build_history_depth=$(profile_value BUILD_HISTORY_DEPTH)
gate_version=$(profile_value GATE_VERSION)
gate_branch=${GATE_BRANCH:-sysroot/$release}
builder_release=$(profile_value BUILDER_RELEASE)
gate_compiler_name=$(profile_value GATE_COMPILER_NAME)
gate_cc=${GATE_CC:-$(profile_value GATE_CC)}
gate_cxx=${GATE_CXX:-$(profile_value GATE_CXX)}
gate_lint_mode=$(profile_value GATE_LINT_MODE)
gate_compiler_root=$(dirname "$(dirname "$gate_cc")")
gate_prefix_map_flag=$(profile_value GATE_PREFIX_MAP_FLAG)
gate_compiler_package=$(profile_value GATE_COMPILER_PACKAGE)
gate_jdk_package=$(profile_value GATE_JDK_PACKAGE)
gate_java_root=$(profile_value GATE_JAVA_ROOT)
mf2tar_rust_toolchain=$(profile_value MF2TAR_RUST_TOOLCHAIN)
mf2tar_cargo_lock_sha256=$(profile_value MF2TAR_CARGO_LOCK_SHA256)
closed_bins_base_url=$(profile_value CLOSED_BINS_BASE_URL)
closed_bins_archive=$(profile_value CLOSED_BINS_ARCHIVE)
closed_bins_sha256=$(profile_value CLOSED_BINS_SHA256)
closed_bins_nd_archive=$(profile_value CLOSED_BINS_ND_ARCHIVE)
closed_bins_nd_sha256=$(profile_value CLOSED_BINS_ND_SHA256)
closed_bins_cache=${CLOSED_BINS_CACHE:-$workdir/inputs}
source_date_epoch=${SOURCE_DATE_EPOCH:-$(profile_value SOURCE_DATE_EPOCH)}
TMPDIR=${TMPDIR:-$workdir/tmp}
export TMPDIR

[ -n "$release_base_commit" ] || die "missing RELEASE_BASE_COMMIT in $profile"
[ -n "$gate_commit" ] || die "missing BUILD_HEAD_COMMIT in $profile"
[ -n "$build_head_ref" ] || die "missing BUILD_HEAD_REF in $profile"
[ -n "$build_history_depth" ] || die "missing BUILD_HISTORY_DEPTH in $profile"
[ -n "$gate_version" ] || die "missing GATE_VERSION in $profile"
expected_gate_version=$(printf 'sysroot/%s-0-g%.12s' \
	"$release" "$profile_build_commit")
[ "$gate_version" = "$expected_gate_version" ] ||
	die "GATE_VERSION mismatch: expected $expected_gate_version, found $gate_version"
[ -n "$builder_release" ] || die "missing BUILDER_RELEASE in $profile"
[ -n "$gate_compiler_name" ] || die "missing GATE_COMPILER_NAME in $profile"
[ -n "$gate_cc" ] || die "missing GATE_CC in $profile"
[ -n "$gate_cxx" ] || die "missing GATE_CXX in $profile"
[ "$gate_lint_mode" = reproducible-stub ] ||
	die "unsupported GATE_LINT_MODE in $profile: $gate_lint_mode"
[ -n "$gate_prefix_map_flag" ] || die "missing GATE_PREFIX_MAP_FLAG in $profile"
[ -n "$gate_compiler_package" ] || die "missing GATE_COMPILER_PACKAGE in $profile"
[ -n "$gate_jdk_package" ] || die "missing GATE_JDK_PACKAGE in $profile"
[ -n "$gate_java_root" ] || die "missing GATE_JAVA_ROOT in $profile"
[ -n "$mf2tar_rust_toolchain" ] || die "missing MF2TAR_RUST_TOOLCHAIN in $profile"
[ -n "$mf2tar_cargo_lock_sha256" ] ||
	die "missing MF2TAR_CARGO_LOCK_SHA256 in $profile"
[ -n "$closed_bins_base_url" ] || die "missing CLOSED_BINS_BASE_URL in $profile"
[ -n "$closed_bins_archive" ] || die "missing CLOSED_BINS_ARCHIVE in $profile"
[ -n "$closed_bins_sha256" ] || die "missing CLOSED_BINS_SHA256 in $profile"
[ -n "$closed_bins_nd_archive" ] || die "missing CLOSED_BINS_ND_ARCHIVE in $profile"
[ -n "$closed_bins_nd_sha256" ] || die "missing CLOSED_BINS_ND_SHA256 in $profile"
mkdir -p "$TMPDIR"

if [ -n "$source_date_epoch" ]; then
	case "$source_date_epoch" in
	*[!0-9]*)
		die "SOURCE_DATE_EPOCH must be numeric: $source_date_epoch"
		;;
	esac
fi

run_as_root() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	elif command -v pfexec >/dev/null 2>&1; then
		pfexec "$@"
	else
		die "need root or pfexec for: $*"
	fi
}

check_builder_release() {
	case "$(uname -v)" in
	*"$builder_release"*) ;;
	*)
		if [ "${ILLUMOS_SYSROOT_ALLOW_BUILDER_MISMATCH:-}" != 1 ]; then
			die "profile $release requires OmniOS $builder_release; found $(uname -v)"
		fi
		printf 'WARNING: profile %s expects %s; found %s\n' \
			"$release" "$builder_release" "$(uname -v)" >&2
		;;
	esac
}

install_omnios_deps() {
	run_as_root pkg set-publisher -g \
		"https://pkg.omnios.org/$builder_release/extra" extra.omnios
	run_as_root pkg refresh --full
	run_as_root pkg install --accept \
		developer/build/onbld \
		"$gate_compiler_package" \
		developer/build/gnu-make \
		developer/illumos-tools \
		"$gate_jdk_package" \
		developer/versioning/git
}

check_tools() {
	for tool in git gmake gzip tar sed curl digest; do
		command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
	done
	command -v "$awk_cmd" >/dev/null 2>&1 || die "missing required tool: $awk_cmd"
	if [ -n "$source_date_epoch" ]; then
		for tool in perl zip; do
			command -v "$tool" >/dev/null 2>&1 ||
				die "missing required reproducibility tool: $tool"
		done
	fi
	[ -x /opt/onbld/bin/nightly ] || die "missing /opt/onbld/bin/nightly"
	[ -x "$gate_cc" ] || die "missing profile compiler: $gate_cc"
	[ -x "$gate_cxx" ] || die "missing profile C++ compiler: $gate_cxx"
	[ -x "$gate_java_root/bin/jar" ] ||
		die "missing profile JDK jar tool: $gate_java_root/bin/jar"
	if [ "${ILLUMOS_SYSROOT_GATE_ONLY:-}" != 1 ] &&
		! command -v cargo >/dev/null 2>&1; then
		[ -x /opt/ooce/bin/cargo ] || die "missing cargo"
	fi
}

checkout_gate() {
	mkdir -p "$workdir"
	if [ ! -d "$gate_dir/.git" ]; then
		git init "$gate_dir"
	fi
	if [ -f "$gate_repo" ]; then
		git -C "$gate_dir" bundle unbundle "$gate_repo" >/dev/null
		git -C "$gate_dir" cat-file -e "$gate_commit^{commit}"
		git -C "$gate_dir" checkout -B "$gate_branch" "$gate_commit"
	else
		if ! git -C "$gate_dir" remote get-url origin >/dev/null 2>&1; then
			git -C "$gate_dir" remote add origin "$gate_repo"
		fi
		fetch_target=$build_head_ref
		if [ "$gate_commit" != "$profile_build_commit" ]; then
			fetch_target=$gate_commit
		fi
		git -C "$gate_dir" fetch --depth "$build_history_depth" origin "$fetch_target"
		git -C "$gate_dir" checkout -B "$gate_branch" FETCH_HEAD
	fi

	actual_commit=$(git -C "$gate_dir" rev-parse HEAD)
	[ "$actual_commit" = "$gate_commit" ] ||
		die "build head mismatch: expected $gate_commit, found $actual_commit"
	git -C "$gate_dir" cat-file -e "$release_base_commit^{commit}" ||
		die "release base $release_base_commit is absent from fetched history"
	git -C "$gate_dir" merge-base --is-ancestor "$release_base_commit" "$gate_commit" ||
		die "release base $release_base_commit is not an ancestor of $gate_commit"
}

check_gate_has_no_rust() {
	rust_paths=$(git -C "$gate_dir" ls-tree -r --name-only HEAD | "$awk_cmd" '
		/(^|\/)Cargo\.toml$/ || /\.rs$/ { print }
	')
	if [ -n "$rust_paths" ]; then
		printf '%s\n' "$rust_paths" >&2
		die "pinned gate contains Rust or Cargo sources"
	fi
}

sha256_file() {
	digest -a sha256 "$1"
}

fetch_verified_input() {
	url=$1
	expected=$2
	destination=$3

	if [ -f "$destination" ]; then
		actual=$(sha256_file "$destination")
		[ "$actual" = "$expected" ] ||
			die "cached input checksum mismatch for $destination: $actual"
		return
	fi

	temporary=$destination.part
	rm -f "$temporary"
	curl -fL --retry 3 -o "$temporary" "$url"
	actual=$(sha256_file "$temporary")
	[ "$actual" = "$expected" ] || {
		rm -f "$temporary"
		die "downloaded input checksum mismatch for $url: $actual"
	}
	mv "$temporary" "$destination"
}

prepare_closed_bins() {
	mkdir -p "$closed_bins_cache"
	closed_archive_path=$closed_bins_cache/$closed_bins_archive
	closed_nd_archive_path=$closed_bins_cache/$closed_bins_nd_archive
	fetch_verified_input "$closed_bins_base_url/$closed_bins_archive" \
		"$closed_bins_sha256" "$closed_archive_path"
	fetch_verified_input "$closed_bins_base_url/$closed_bins_nd_archive" \
		"$closed_bins_nd_sha256" "$closed_nd_archive_path"

	closed_stage=$workdir/closed-bins
	closed_stamp=$closed_stage/closed-inputs.sha256
	expected_stamp="$closed_bins_sha256  $closed_bins_archive
$closed_bins_nd_sha256  $closed_bins_nd_archive"
	if [ -d "$closed_stage" ]; then
		[ -f "$closed_stamp" ] ||
			die "refusing unverified closed-bins directory: $closed_stage"
		actual_stamp=$(cat "$closed_stamp")
		[ "$actual_stamp" = "$expected_stamp" ] ||
			die "closed-bins input stamp mismatch: $closed_stamp"
	else
		mkdir -p "$closed_stage"
		tar xjpf "$closed_archive_path" -C "$closed_stage"
		tar xjpf "$closed_nd_archive_path" -C "$closed_stage"
		printf '%s\n' "$expected_stamp" > "$closed_stamp"
	fi
	closed_bins_dir=$closed_stage/closed
	[ -d "$closed_bins_dir" ] ||
		die "closed-bins archives did not produce $closed_bins_dir"
}

prepare_env_file() {
	cp "$env_file" "$gate_dir/illumos.$release.sh"
	if [ -n "$source_date_epoch" ]; then
		dtrace_suffix=$(printf '%07d' "$((source_date_epoch % 10000000))")
		repro_tools_dir=$workdir/repro-tools
		pkg_publication_timestamp=$(
			perl -MPOSIX=strftime -e \
				'print strftime("%Y%m%dT%H%M%SZ", gmtime($ARGV[0])), "\n"' \
				"$source_date_epoch"
		)
		release_date=$(
			LC_ALL=C perl -MPOSIX=strftime -e \
				'print strftime("%B %Y", gmtime($ARGV[0])), "\n"' \
				"$source_date_epoch"
		)
		cat >> "$gate_dir/illumos.$release.sh" <<EOF

# Reproducible sysroot build settings from $0
export SOURCE_DATE_EPOCH=$source_date_epoch
export ILLUMOS_SYSROOT_GATE_DIR="$gate_dir"
export ILLUMOS_SYSROOT_DTRACE_KEY=$dtrace_suffix
export ILLUMOS_SYSROOT_DTRACE_SUFFIX=$dtrace_suffix
export RELEASE_DATE="$release_date"
export VERSION="$gate_version"
export BUILDVERSION_EXEC="$repro_tools_dir/buildversion"
export PRIMARY_CC=$gate_compiler_name,$repro_tools_dir/gcc,gnu
export PRIMARY_CCC=$gate_compiler_name,$repro_tools_dir/g++,gnu
export GCC_ROOT=$gate_compiler_root
export GNUC_ROOT=$gate_compiler_root
export BUILD_LINT=$repro_tools_dir/lint
export DTRACE="$repro_tools_dir/dtrace -xnolibs"
export PKG_PUBLICATION_TIMESTAMP=$pkg_publication_timestamp
export ILLUMOS_SYSROOT_REAL_JAR="$gate_java_root/bin/jar"
EOF
	fi
	cat >> "$gate_dir/illumos.$release.sh" <<EOF

# Verified stock closed bins from $0
export ON_CLOSED_BINS="$closed_bins_dir"
EOF
	if [ -n "$jobs" ]; then
		printf '\n# Override from %s\nexport DMAKE_MAX_JOBS=%s\n' "$0" "$jobs" \
			>> "$gate_dir/illumos.$release.sh"
	fi
	/bin/ksh93 -n "$gate_dir/illumos.$release.sh"
}

prepare_repro_tools() {
	if [ -z "$source_date_epoch" ]; then
		return
	fi

	repro_tools_dir=$workdir/repro-tools
	mkdir -p "$repro_tools_dir"
	canonical_gate_dir=/tmp/illumos-sysroot-gate-$release
	if [ "$release" = 20181213 ]; then
		if [ -L "$canonical_gate_dir" ]; then
			rm -f "$canonical_gate_dir"
		elif [ -e "$canonical_gate_dir" ]; then
			die "refusing non-symlink canonical gate path: $canonical_gate_dir"
		fi
		ln -s "$gate_dir" "$canonical_gate_dir"
	fi
	cp /opt/onbld/bin/nightly "$repro_tools_dir/nightly"
	REPRO_NIGHTLY_TMPROOT=$TMPDIR perl -pi -e '
	    if ($_ eq qq{TMPDIR="/tmp/nightly.tmpdir.\$\$"\n}) {
		$_ = qq{TMPDIR="$ENV{REPRO_NIGHTLY_TMPROOT}/nightly.tmpdir.\$\$"\n};
	    }
	' "$repro_tools_dir/nightly"
	expected_nightly_tmpdir='TMPDIR="'"$TMPDIR"'/nightly.tmpdir.$$"'
	grep -Fxq "$expected_nightly_tmpdir" "$repro_tools_dir/nightly" ||
		die "patching nightly temporary directory"
	chmod +x "$repro_tools_dir/nightly"
	pkg_python=$(sed -n '1s/^#![[:space:]]*\([^[:space:]]*\).*/\1/p' /usr/bin/pkg)
	[ -n "$pkg_python" ] && [ -x "$pkg_python" ] ||
		die "could not determine IPS Python interpreter from /usr/bin/pkg"
	cat > "$repro_tools_dir/jar" <<'EOF'
#!/usr/bin/perl
#
# Run the JDK jar tool, then normalize created or updated archives.

use strict;
use warnings;
use Cwd qw(getcwd);
use File::Find;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);

my $real_jar = $ENV{ILLUMOS_SYSROOT_REAL_JAR} || "/usr/bin/jar";
my $epoch = $ENV{SOURCE_DATE_EPOCH};

sub old_style_options {
	my ($arg) = @_;
	$arg =~ s/^-//;
	return undef if $arg =~ /^-/;
	return undef unless $arg =~ /[ctxuid]/;
	return undef unless $arg =~ /^[A-Za-z0-9]+$/;
	return $arg;
}

sub archive_arg {
	my (@args) = @_;

	for (my $i = 0; $i < @args; $i++) {
		my $arg = $args[$i];
		return $args[$i + 1] if ($arg eq "-f" || $arg eq "--file");
		return $1 if ($arg =~ /^--file=(.*)$/);

		my $opts = old_style_options($arg);
		next unless defined($opts) && $opts =~ /f/;

		my $operand = $i + 1;
		for my $ch (split //, $opts) {
			if ($ch eq "f") {
				return $args[$operand];
			}
			if ($ch eq "m" || $ch eq "e") {
				$operand++;
			}
		}
	}

	return undef;
}

sub changes_archive {
	my (@args) = @_;

	for my $arg (@args) {
		return 1 if ($arg eq "-c" || $arg eq "--create");
		return 1 if ($arg eq "-u" || $arg eq "--update");
		my $opts = old_style_options($arg);
		return 1 if defined($opts) && $opts =~ /[cu]/;
	}

	return 0;
}

sub epoch_date_string {
	my @wday = qw(Sun Mon Tue Wed Thu Fri Sat);
	my @mon = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	my @t = gmtime($epoch);
	return sprintf("%s %s %2d %02d:%02d:%02d UTC %04d",
	    $wday[$t[6]], $mon[$t[4]], $t[3], $t[2], $t[1], $t[0],
	    $t[5] + 1900);
}

sub normalize_manifest {
	my ($root) = @_;
	my $manifest = File::Spec->catfile($root, "META-INF", "MANIFEST.MF");
	return unless -f $manifest;

	open(my $in, "<", $manifest) or die "open $manifest: $!\n";
	binmode($in);
	local $/;
	my $text = <$in>;
	close($in) or die "close $manifest: $!\n";

	my $repro_date = epoch_date_string();
	$text =~ s{(^Implementation-Version: \[)[^\]\r\n]*(\]\r?$)}
	    {$1$repro_date$2}mg;

	open(my $out, ">", $manifest) or die "open $manifest: $!\n";
	binmode($out);
	print $out $text;
	close($out) or die "close $manifest: $!\n";
}

sub normalize_jar {
	my ($jar) = @_;
	die "SOURCE_DATE_EPOCH must be numeric\n"
	    unless defined($epoch) && $epoch =~ /^[0-9]+$/;

	my $cwd = getcwd();
	my $jar_abs = File::Spec->rel2abs($jar, $cwd);
	return unless -f $jar_abs;

	my ($volume, $directories) = File::Spec->splitpath($jar_abs);
	my $jar_dir = File::Spec->catpath($volume, $directories, "");
	my $tmp = tempdir(".illumos-sysroot-jar.XXXXXX",
	    DIR => $jar_dir, CLEANUP => 1);
	my $root = File::Spec->catdir($tmp, "root");
	make_path($root);

	chdir($root) or die "chdir $root: $!\n";
	system($real_jar, "xf", $jar_abs) == 0
	    or die "extracting $jar_abs failed\n";

	normalize_manifest($root);

	my @entries;
	find({
	    no_chdir => 1,
	    wanted => sub {
		return if $_ eq ".";
		my $rel = $_;
		$rel =~ s{^\./}{};
		utime($epoch, $epoch, $_)
		    or die "utime $rel: $!\n";
		$rel .= "/" if -d $_ && $rel !~ m{/$};
		push @entries, $rel;
	    },
	}, ".");

	my %seen = map { $_ => 1 } @entries;
	my @ordered;
	for my $first ("META-INF/", "META-INF/MANIFEST.MF") {
		if (delete $seen{$first}) {
			push @ordered, $first;
		}
	}
	push @ordered, sort keys %seen;
	die "refusing to write empty jar: $jar_abs\n" unless @ordered;

	my $tmpjar = File::Spec->catfile($tmp, "out.jar");
	open(my $zip, "|-", "/usr/bin/zip", "-X", "-q", $tmpjar, "-@")
	    or die "starting zip: $!\n";
	print $zip "$_\n" for @ordered;
	close($zip) or die "zip failed\n";

	chdir($cwd) or die "chdir $cwd: $!\n";
	rename($tmpjar, $jar_abs) or die "rename $tmpjar $jar_abs: $!\n";
}

my $jar = archive_arg(@ARGV);
my $must_normalize = defined($jar) && changes_archive(@ARGV);

system($real_jar, @ARGV);
my $status = $?;
exit($status >> 8) if $status != 0;

normalize_jar($jar) if $must_normalize;
exit 0;
EOF
	cat > "$repro_tools_dir/dtrace" <<'EOF'
#!/bin/sh
#
# Normalize dtrace -G generated object symbols from the build-host dtrace.

set -u

real_dtrace=${ILLUMOS_SYSROOT_REAL_DTRACE:-/usr/sbin/dtrace}
ftok_preload=${ILLUMOS_SYSROOT_DTRACE_FTOK_PRELOAD:-$(dirname "$0")/dtrace-ftok.so}
is_generate=false
out=
script=
objects=
expect_out=false
expect_script=false

for arg
do
	if $expect_out; then
		out=$arg
		expect_out=false
		continue
	fi
	if $expect_script; then
		script=$arg
		expect_script=false
		continue
	fi

	case "$arg" in
	-G)
		is_generate=true
		;;
	-o)
		expect_out=true
		;;
	-o*)
		out=${arg#-o}
		;;
	-s)
		expect_script=true
		;;
	-s*)
		script=${arg#-s}
		;;
	*.o)
		objects="$objects $arg"
		;;
	esac
done

set +e
LD_PRELOAD_64="$ftok_preload" "$real_dtrace" "$@"
status=$?
set -e
[ "$status" -eq 0 ] || exit "$status"

if $is_generate && [ -n "${ILLUMOS_SYSROOT_DTRACE_SUFFIX:-}" ]; then
	files=$objects
	if [ -n "$out" ]; then
		files="$out $files"
	elif [ -n "$script" ]; then
		base=${script##*/}
		case "$script" in
		*.d)
			candidate=${script%.*}.o
			[ ! -f "$candidate" ] || files="$candidate $files"
			;;
		esac
		case "$base" in
		*.d)
			candidate=${base%.*}.o
			[ ! -f "$candidate" ] || files="$candidate $files"
			;;
		esac
		[ ! -f dtrace.o ] || files="dtrace.o $files"
	fi
	set -- $files
	if [ "$#" -gt 0 ]; then
		perl - "$@" <<'PERL'
use strict;
use warnings;

my $suffix = $ENV{"ILLUMOS_SYSROOT_DTRACE_SUFFIX"};
die "ILLUMOS_SYSROOT_DTRACE_SUFFIX must be seven digits\n"
    unless defined($suffix) && $suffix =~ /^[0-9]{7}$/;

sub u32le {
	my ($data, $offset) = @_;
	return unpack("V", substr($data, $offset, 4));
}

sub u64le_small {
	my ($data, $offset) = @_;
	my $low = u32le($data, $offset);
	my $high = u32le($data, $offset + 4);
	return undef if $high != 0;
	return $low;
}

sub normalize_dof {
	my ($dataref) = @_;
	my $cursor = 0;
	my $changed = 0;

	while ((my $base = index($$dataref, "\x7fDOF", $cursor)) >= 0) {
		$cursor = $base + 4;
		next if $base + 64 > length($$dataref);
		next unless ord(substr($$dataref, $base + 5, 1)) == 1;

		my $hdrsize = u32le($$dataref, $base + 20);
		my $secsize = u32le($$dataref, $base + 24);
		my $secnum = u32le($$dataref, $base + 28);
		my $secoff = u64le_small($$dataref, $base + 32);
		my $filesz = u64le_small($$dataref, $base + 48);
		next unless defined($secoff) && defined($filesz);
		next unless $hdrsize >= 64 && $secsize >= 32;
		next if $base + $filesz > length($$dataref);
		next if $secoff + $secnum * $secsize > $filesz;

		for my $i (0 .. $secnum - 1) {
			my $section = $base + $secoff + $i * $secsize;
			my $type = u32le($$dataref, $section);
			my $offset = u64le_small($$dataref, $section + 16);
			my $size = u64le_small($$dataref, $section + 24);
			next unless defined($offset) && defined($size);
			next if $offset + $size > $filesz;

			if ($type == 20 && $size >= 257 * 5) {
				my $fixed = "illumos-sysroot";
				my $nodename = $fixed . "\0" x (257 - length($fixed));
				my $field = $base + $offset + 257;
				if (substr($$dataref, $field, 257) ne $nodename) {
					substr($$dataref, $field, 257) = $nodename;
					$changed = 1;
				}
				next;
			}

			next unless $type == 5;
			my $entsize = u32le($$dataref, $section + 12);
			next unless $entsize >= 32 && $size % $entsize == 0;

			for (my $action = 0; $action < $size; $action += $entsize) {
				my $uarg = $base + $offset + $action + 24;
				my $zero = "\0" x 8;
				if (substr($$dataref, $uarg, 8) ne $zero) {
					substr($$dataref, $uarg, 8) = $zero;
					$changed = 1;
				}
			}
		}

		$cursor = $base + $filesz;
	}

	return $changed;
}

for my $path (@ARGV) {
	open(my $in, "<", $path) or die "open $path: $!\n";
	binmode($in);
	local $/;
	my $data = <$in>;
	close($in) or die "close $path: $!\n";

	my $changed = ($data =~ s/\$dtrace[0-9]{7}/\$dtrace$suffix/g);
	$changed += normalize_dof(\$data);
	next unless $changed;

	open(my $out, ">", $path) or die "open $path: $!\n";
	binmode($out);
	print $out $data;
	close($out) or die "close $path: $!\n";
}
PERL
	fi
fi
EOF
	cat > "$repro_tools_dir/dtrace-ftok.c" <<'EOF'
#include <stdlib.h>
#include <sys/types.h>

key_t
ftok(const char *path, int id)
{
	const char *key = getenv("ILLUMOS_SYSROOT_DTRACE_KEY");

	(void) path;
	(void) id;
	return ((key_t)strtol(key, NULL, 10));
}
EOF
	"$gate_cc" -m64 -fPIC -shared \
		-o "$repro_tools_dir/dtrace-ftok.so" \
		"$repro_tools_dir/dtrace-ftok.c"
	cat > "$repro_tools_dir/sqlite2-normalize.c" <<'EOF'
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "sqlite.h"

static const unsigned char sqlite2_magic[] =
    "** This file contains an SQLite 2.1 database **";

static void
fatal(const char *path, const char *what)
{
	(void) fprintf(stderr, "%s: %s: %s\n", path, what, strerror(errno));
	exit(1);
}

int
main(int argc, char **argv)
{
	unsigned long cookie;
	unsigned char header[64];
	unsigned char encoded[4];
	char *end = NULL;
	char *error = NULL;
	sqlite *db;
	int fd;

	if (argc != 3) {
		(void) fprintf(stderr, "usage: %s COOKIE SQLITE2_DB\n", argv[0]);
		return (2);
	}

	errno = 0;
	cookie = strtoul(argv[1], &end, 10);
	if (errno != 0 || end == argv[1] || *end != '\0' ||
	    cookie > UINT32_MAX) {
		(void) fprintf(stderr, "invalid cookie: %s\n", argv[1]);
		return (2);
	}

	db = sqlite_open(argv[2], 0600, &error);
	if (db == NULL) {
		(void) fprintf(stderr, "%s: sqlite_open: %s\n", argv[2],
		    error != NULL ? error : "unknown error");
		free(error);
		return (1);
	}
	if (sqlite_exec(db, "VACUUM;", NULL, NULL, &error) != SQLITE_OK) {
		(void) fprintf(stderr, "%s: VACUUM: %s\n", argv[2],
		    error != NULL ? error : "unknown error");
		free(error);
		sqlite_close(db);
		return (1);
	}
	sqlite_close(db);

	fd = open(argv[2], O_RDWR);
	if (fd < 0)
		fatal(argv[2], "open");
	if (pread(fd, header, sizeof (header), 0) != sizeof (header))
		fatal(argv[2], "read header");
	if (memcmp(header, sqlite2_magic, sizeof (sqlite2_magic)) != 0 ||
	    header[48] != 0x28 || header[49] != 0x75 ||
	    header[50] != 0xe3 || header[51] != 0xda) {
		(void) fprintf(stderr, "%s: unsupported SQLite 2 header\n", argv[2]);
		(void) close(fd);
		return (1);
	}

	encoded[0] = cookie & 0xff;
	encoded[1] = (cookie >> 8) & 0xff;
	encoded[2] = (cookie >> 16) & 0xff;
	encoded[3] = (cookie >> 24) & 0xff;
	if (pwrite(fd, encoded, sizeof (encoded), 60) != sizeof (encoded))
		fatal(argv[2], "write schema cookie");
	if (fsync(fd) != 0)
		fatal(argv[2], "fsync");
	if (close(fd) != 0)
		fatal(argv[2], "close");

	return (0);
}
EOF
	cat > "$repro_tools_dir/proto-normalize" <<'EOF'
#!/usr/bin/perl

use strict;
use warnings;
use File::Find;

my $epoch = shift @ARGV;
die "usage: $0 EPOCH ROOT...\n"
    unless defined($epoch) && $epoch =~ /^[0-9]+$/ && @ARGV;

sub normalize_pyc {
	my ($path) = @_;
	my @metadata = stat($path);
	die "stat $path: $!\n" unless @metadata;
	my $mode = $metadata[2] & 07777;
	my $made_writable = !($mode & 0200);
	chmod($mode | 0200, $path) == 1 or die "chmod $path: $!\n"
	    if $made_writable;
	open(my $file, "+<", $path) or die "open $path: $!\n";
	binmode($file);
	my $magic;
	read($file, $magic, 4) == 4 or die "read magic $path: $!\n";
	seek($file, 4, 0) or die "seek $path: $!\n";
	print {$file} pack("V", $epoch) or die "write timestamp $path: $!\n";
	close($file) or die "close $path: $!\n";
	chmod($mode, $path) == 1 or die "restore mode $path: $!\n"
	    if $made_writable;
}

sub normalize_javadoc {
	my ($path) = @_;
	open(my $in, "<", $path) or die "open $path: $!\n";
	local $/;
	my $html = <$in>;
	close($in) or die "close $path: $!\n";

	$html =~ s{(<tbody>\n)(.*?)(</tbody>)}{
		my ($open, $body, $close) = ($1, $2, $3);
		my @rows = ($body =~
		    m{(<tr class="(?:altColor|rowColor)">.*?</tr>\n?)}sg);
		my $remainder = $body;
		$remainder =~
		    s{<tr class="(?:altColor|rowColor)">.*?</tr>\n?}{}sg;
		if (@rows && $remainder !~ /\S/) {
			for my $row (@rows) {
				$row =~ s{<tr class="(?:altColor|rowColor)">}
				    {<tr class="COLOR">};
			}
			@rows = sort @rows;
			for (my $i = 0; $i < @rows; $i++) {
				my $class = $i % 2 == 0 ? "altColor" : "rowColor";
				$rows[$i] =~
				    s{<tr class="COLOR">}{<tr class="$class">};
			}
			$body = join("", @rows);
		}
		$open . $body . $close;
	}esg;

	my @lines = split(/(?<=\n)/, $html);
	my (@output, @items);
	for my $line (@lines) {
		if ($line =~ /^\s*<li type="circle">.*<\/li>\s*$/) {
			push @items, $line;
			next;
		}
		push @output, sort @items;
		@items = ();
		push @output, $line;
	}
	push @output, sort @items;
	my $normalized = join("", @output);
	return if $normalized eq $html;

	my @metadata = stat($path);
	die "stat $path: $!\n" unless @metadata;
	my $mode = $metadata[2] & 07777;
	my $made_writable = !($mode & 0200);
	chmod($mode | 0200, $path) == 1 or die "chmod $path: $!\n"
	    if $made_writable;
	open(my $out, ">", $path) or die "open $path: $!\n";
	print {$out} $normalized or die "write $path: $!\n";
	close($out) or die "close $path: $!\n";
	chmod($mode, $path) == 1 or die "restore mode $path: $!\n"
	    if $made_writable;
}

for my $root (@ARGV) {
	next unless -d $root;
	find({
		no_chdir => 1,
		wanted => sub {
			return unless -f $_;
			if (/\.pyc$/) {
				normalize_pyc($_);
			} elsif (/\.html$/ &&
			    m{/usr/share/lib/java/javadoc/}) {
				normalize_javadoc($_);
			}
		},
	}, $root);
}
EOF
	cat > "$repro_tools_dir/svccfg" <<EOF
#!/bin/sh

set -eu

real=\$1
shift
if [ "\${1:-}" = import ] && [ "\$#" -eq 2 ]; then
	input=\$2
	input_dir=\$(dirname -- "\$input")
	input_base=\${input##*/}
	input_dir=\$(CDPATH= cd -- "\$input_dir" && pwd)
	input=\$input_dir/\$input_base
	case "\$input" in
	"$gate_dir"/*)
		relative=\${input#"$gate_dir"/}
		canonical="/tmp/illumos-sysroot-svccfg-$release/\$relative"
		mkdir -p "\$(dirname -- "\$canonical")"
		cp "\$input" "\$canonical"
		set -- import "\$canonical"
		;;
	*)
		echo "ERROR: svccfg import escaped the gate: \$input" >&2
		exit 1
		;;
	esac
fi
exec "\$real" "\$@"
EOF
	cat > "$repro_tools_dir/pkg-tool.py" <<'EOF'
"""Run an IPS command with reproducible time and iteration order."""

import datetime
import os
import runpy
import sys

epoch = int(os.environ["SOURCE_DATE_EPOCH"])
real_datetime = datetime.datetime
fixed = real_datetime.utcfromtimestamp(epoch)


class ReproducibleDateTime(real_datetime):
    @classmethod
    def utcnow(cls):
        return cls(fixed.year, fixed.month, fixed.day, fixed.hour,
                   fixed.minute, fixed.second, fixed.microsecond)

    @classmethod
    def now(cls, tz=None):
        value = cls.utcnow()
        if tz is None:
            return value
        return tz.fromutc(value.replace(tzinfo=tz))


datetime.datetime = ReproducibleDateTime
tool = sys.argv.pop(1)
if os.path.basename(tool) == "pkgrepo":
    try:
        import pkg.site_paths
    except ImportError:
        # Older IPS releases expose pkg.indexer directly and have no
        # pkg.site_paths module.  Importing the repository first also avoids
        # a circular import between pkg.lockfile and pkg.catalog there.
        import pkg.server.repository
    else:
        # Newer IPS adds the pycurl module directory here.  Match the stock
        # pkgrepo initialization order before importing the repository.
        pkg.site_paths.init()
        import pkg.server.repository
    import pkg.indexer

    original_process_fmris = pkg.indexer.Indexer._process_fmris

    def reproducible_process_fmris(self, fmris):
        # IPS assigns manifest IDs in input order; catalog insertion order varies.
        return original_process_fmris(self, sorted(fmris, key=str))

    pkg.indexer.Indexer._process_fmris = reproducible_process_fmris

sys.argv[0] = tool
runpy.run_path(tool, run_name="__main__")
EOF
	for pkg_tool in pkgdepend pkgrepo pkgsend; do
		cat > "$repro_tools_dir/$pkg_tool" <<EOF
#!/bin/sh

set -eu

tool=\${0##*/}
tool_dir=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
export PYTHONHASHSEED=0
exec "$pkg_python" -s "\$tool_dir/pkg-tool.py" "/usr/bin/\$tool" "\$@"
EOF
	done
	cat > "$repro_tools_dir/lint" <<'EOF'
#!/bin/sh
#
# The old gate installs lint-library side products even when nightly was not
# asked to run a lint pass.  Sun Studio lint is no longer a durable input, so
# create deterministic placeholders for those non-runtime build products.

set -eu

output=
dirout=
sources=
want_output=false
for arg do
	if $want_output; then
		output=$arg
		want_output=false
		continue
	fi
	case "$arg" in
	-o) want_output=true ;;
	-dirout=*) dirout=${arg#-dirout=} ;;
	*.c) sources="$sources $arg" ;;
	esac
done

if [ -n "$output" ]; then
	: > "llib-l$output.ln"
fi
if [ -n "$dirout" ]; then
	mkdir -p "$dirout"
	for source in $sources; do
		base=${source##*/}
		: > "$dirout/${base%.c}.ln"
	done
fi
EOF
	cat > "$repro_tools_dir/buildversion" <<'EOF'
#!/bin/sh

set -eu
: "${VERSION:?}"
printf '%s\n' "$VERSION"
EOF
	for compiler in gcc g++; do
		case "$compiler" in
		gcc) real_compiler=$gate_cc ;;
		g++) real_compiler=$gate_cxx ;;
		esac
		if [ "$release" = 20181213 ]; then
			cat > "$repro_tools_dir/$compiler" <<EOF
#!/bin/sh

set -eu

compiler=\${0##*/}
: "\${ILLUMOS_SYSROOT_GATE_DIR:?}"
remaining=\$#
while [ "\$remaining" -gt 0 ]; do
	arg=\$1
	shift
	case "\$arg" in
	"\$ILLUMOS_SYSROOT_GATE_DIR"/*)
		arg="$canonical_gate_dir/\${arg#"\$ILLUMOS_SYSROOT_GATE_DIR"/}"
		;;
	esac
	set -- "\$@" "\$arg"
	remaining=\$((remaining - 1))
done
exec "$real_compiler" \
	"${gate_prefix_map_flag}=\${ILLUMOS_SYSROOT_GATE_DIR}=." \
	"${gate_prefix_map_flag}=$canonical_gate_dir=." "\$@"
EOF
		else
			cat > "$repro_tools_dir/$compiler" <<EOF
#!/bin/sh

set -eu

compiler=\${0##*/}
: "\${ILLUMOS_SYSROOT_GATE_DIR:?}"
exec "$real_compiler" \
	"${gate_prefix_map_flag}=\${ILLUMOS_SYSROOT_GATE_DIR}=." "\$@"
EOF
		fi
	done
	chmod +x "$repro_tools_dir/jar" "$repro_tools_dir/dtrace" \
		"$repro_tools_dir/gcc" "$repro_tools_dir/g++" \
		"$repro_tools_dir/lint" "$repro_tools_dir/buildversion" \
		"$repro_tools_dir/proto-normalize" "$repro_tools_dir/svccfg" \
		"$repro_tools_dir/pkgdepend" "$repro_tools_dir/pkgrepo" \
		"$repro_tools_dir/pkgsend"
}

apply_gate_repro_patches() {
	if [ -z "$source_date_epoch" ]; then
		return
	fi

	if ! grep -q 'ILLUMOS_SYSROOT_DTRACE_KEY' \
		"$gate_dir/usr/src/lib/libdtrace/common/dt_link.c"; then
		perl -0pi -e '
		    s/char \*s, \*p, \*r;/char *s, *p, *r, *repro_key;/ or die;
		    s/if \(\(objkey = ftok\(obj, 0\)\) == \(key_t\)-1\) \{\n\t\treturn \(dt_link_error\(dtp, elf, fd, bufs,\n\t\t    "failed to generate unique key for object file: %s", obj\)\);\n\t\}/if ((repro_key = getenv("ILLUMOS_SYSROOT_DTRACE_KEY")) != NULL \&\&\n\t    repro_key[0] != 0) {\n\t\tobjkey = (key_t)strtol(repro_key, NULL, 10);\n\t} else if ((objkey = ftok(obj, 0)) == (key_t)-1) {\n\t\treturn (dt_link_error(dtp, elf, fd, bufs,\n\t\t    "failed to generate unique key for object file: %s", obj));\n\t}/ or die;
		' "$gate_dir/usr/src/lib/libdtrace/common/dt_link.c"
	fi

	if ! grep -q 'PKG_PUBLICATION_TIMESTAMP' "$gate_dir/usr/src/pkg/Makefile"; then
		REPRO_PKGSEND=$repro_tools_dir/pkgsend perl -0pi -e '
		    my $old_package_chain = index($_, "\$(PDIR)/%.fin:") < 0;
		    if (!$old_package_chain) {
			my $fin = "\t\t    \$(<) \$(PM_FINAL_TRANSFORMS); \\\n";
			my $ts = "\t\tif [ -n \"\$(PKG_PUBLICATION_TIMESTAMP)\" ]; then \\\n" .
			    "\t\t\t\$(SED) -e \"/^set name=pkg.fmri value=/s/\$\$\/:\$(PKG_PUBLICATION_TIMESTAMP)\/\" \\\n" .
			    "\t\t\t    \$(@) > \$(@).timestamped; \\\n" .
			    "\t\t\t\$(MV) \$(@).timestamped \$(@); \\\n" .
			    "\t\tfi; \\\n";
			s/\Q$fin\E/$fin$ts/ or die;
		    }
		    my $pub = "\t\tpkgsend -s file://\$(PKGDEST)/repo.\$\$r publish \\\n";
		    my $pubts = "";
		    if ($old_package_chain) {
			$pubts .= "\t\tif [ -n \"\$(PKG_PUBLICATION_TIMESTAMP)\" ]; then \\\n" .
			    "\t\t\t\$(SED) -e \"/^set name=pkg.fmri value=/s/\$\$\/:\$(PKG_PUBLICATION_TIMESTAMP)\/\" \\\n" .
			    "\t\t\t    \$(<) > \$(<).timestamped; \\\n" .
			    "\t\t\t\$(MV) \$(<).timestamped \$(<); \\\n" .
			    "\t\tfi; \\\n";
		    }
		    $pubts .= "\t\tif [ -n \"\$(PKG_PUBLICATION_TIMESTAMP)\" ]; then \\\n" .
			"\t\t\tPKGSEND=\"$ENV{REPRO_PKGSEND} -D allow-timestamp\"; \\\n" .
			"\t\telse \\\n" .
			"\t\t\tPKGSEND=$ENV{REPRO_PKGSEND}; \\\n" .
			"\t\tfi; \\\n" .
			"\t\t\$\$PKGSEND -s file://\$(PKGDEST)/repo.\$\$r publish \\\n";
		    s/\Q$pub\E/$pubts/ or die;
		' "$gate_dir/usr/src/pkg/Makefile"
	fi

	if [ -f "$gate_dir/usr/src/lib/ssp_ns/Makefile.com" ] &&
		[ -x /usr/bin/gar ] &&
		! grep -q '^ARFLAGS[	 ]*=.*crD' "$gate_dir/usr/src/lib/ssp_ns/Makefile.com"; then
		perl -0pi -e '
		    my $needle = "include ../../Makefile.lib\n";
		    my $insert = "\nAR =\t\t/usr/bin/gar\nARFLAGS =\tcrD\n";
		    s/\Q$needle\E/$needle$insert/ or die;
		' "$gate_dir/usr/src/lib/ssp_ns/Makefile.com"
	fi

	repro_tools_dir=$workdir/repro-tools
	if [ "$release" = 20181213 ]; then
		spellin=$gate_dir/usr/src/cmd/spell/spellin.c
		if grep -Fq 'table = (unsigned *)malloc(ND * sizeof (*table));' \
			"$spellin"; then
			perl -0pi -e '
			    s/table = \(unsigned \*\)malloc\(ND \* sizeof \(\*table\)\);/
			      table = (unsigned *)calloc(ND, sizeof (*table));/ or die;
			' "$spellin"
		fi
		grep -Fq 'table = (unsigned *)calloc(ND, sizeof (*table));' \
			"$spellin" || die "patching deterministic spell table allocation"

		seed_makefile=$gate_dir/usr/src/cmd/svc/seed/Makefile
		if ! grep -Fq "$repro_tools_dir/svccfg" "$seed_makefile"; then
			REPRO_SVCCFG=$repro_tools_dir/svccfg perl -0pi -e '
			    my $variable = "SVCCFG = ../svccfg/svccfg-native\n";
			    my $insert = $variable .
				"REPRO_SVCCFG = $ENV{REPRO_SVCCFG}\n";
			    s/\Q$variable\E/$insert/ or die;
			    s/\$\(SVCCFG\) import \$\$m/\$(REPRO_SVCCFG) \$(SVCCFG) import \$\$m/g;
			' "$seed_makefile"
		fi
		grep -Fq '$(REPRO_SVCCFG) $(SVCCFG) import $$m' \
			"$seed_makefile" || die "patching deterministic svccfg imports"

		pkg_makefile=$gate_dir/usr/src/pkg/Makefile
		if ! grep -Fq "$repro_tools_dir/proto-normalize" "$pkg_makefile"; then
			REPRO_PROTO=$repro_tools_dir/proto-normalize perl -0pi -e '
			    my $target = "\$(PUB_PKGS): stage-licenses\n";
			    my $insert =
				"REPRO_PROTO = $ENV{REPRO_PROTO}\n" .
				"REPRO_PROTO_STAMP = \$(PDIR)/.repro-proto\n\n" .
				"\$(REPRO_PROTO_STAMP): \$(PDIR)/gendeps\n" .
				"\t\$(REPRO_PROTO) \$(SOURCE_DATE_EPOCH) " .
				    "\$(PKGROOT) \$(TOOLSROOT)\n" .
				"\t\$(TOUCH) \$(@)\n\n" .
				"\$(PUB_PKGS): stage-licenses \$(REPRO_PROTO_STAMP)\n";
			    s/\Q$target\E/$insert/ or die;
			' "$pkg_makefile"
		fi
		grep -Fq '$(PUB_PKGS): stage-licenses $(REPRO_PROTO_STAMP)' \
			"$pkg_makefile" || die "patching proto normalization"
	fi
	if ! grep -q 'ILLUMOS_SYSROOT_REPRO_SQLITE' \
		"$gate_dir/usr/src/lib/libsqlite/Makefile.com"; then
		perl -0pi -e '
		    my $old = "\$(NATIVETARGETS) :=\tCPPFLAGS = \$(MYCPPFLAGS)\n";
		    my $new = "\$(NATIVETARGETS) :=\tCPPFLAGS = \$(MYCPPFLAGS) " .
			"-DILLUMOS_SYSROOT_REPRO_SQLITE\n";
		    s/\Q$old\E/$new/ or die;
		' "$gate_dir/usr/src/lib/libsqlite/Makefile.com"

		perl -0pi -e '
		    my $needle = "  assert( size == ROUNDUP(size) );\n" .
			"  assert( start == ROUNDUP(start) );\n" .
			"  assert( pPage->isInit );\n" .
			"  pIdx = \&pPage->u.hdr.firstFree;\n";
		    my $replace = "  assert( size == ROUNDUP(size) );\n" .
			"  assert( start == ROUNDUP(start) );\n" .
			"  assert( pPage->isInit );\n" .
			"#ifdef ILLUMOS_SYSROOT_REPRO_SQLITE\n" .
			"  memset(\&pPage->u.aDisk[start], 0, size);\n" .
			"#endif\n" .
			"  pIdx = \&pPage->u.hdr.firstFree;\n";
		    s/\Q$needle\E/$replace/ or die;
		    my $cell = "  rc = fillInCell(pBt, \&newCell, pKey, nKey, pData, nData);\n";
		    my $zero = "#ifdef ILLUMOS_SYSROOT_REPRO_SQLITE\n" .
			"  memset(\&newCell, 0, sizeof(newCell));\n" .
			"#endif\n" . $cell;
		    s/\Q$cell\E/$zero/ or die;
		' "$gate_dir/usr/src/lib/libsqlite/src/btree.c"

		perl -0pi -e '
		    my $old = "#if OS_UNIX \&\& !defined(SQLITE_TEST)\n";
		    my $new = "#if OS_UNIX \&\& !defined(SQLITE_TEST) \&\& " .
			"!defined(ILLUMOS_SYSROOT_REPRO_SQLITE)\n";
		    s/\Q$old\E/$new/ or die;
		' "$gate_dir/usr/src/lib/libsqlite/src/os.c"

		perl -0pi -e '
		    my $old = "void *sqliteMallocRaw(int n){\n" .
			"  void *p;\n" .
			"  if( (p = malloc(n))==0 ){\n" .
			"    if( n>0 ) sqlite_malloc_failed++;\n" .
			"  }\n" .
			"  return p;\n" .
			"}\n";
		    my $new = "void *sqliteMallocRaw(int n){\n" .
			"  void *p;\n" .
			"  if( (p = malloc(n))==0 ){\n" .
			"    if( n>0 ) sqlite_malloc_failed++;\n" .
			"#ifdef ILLUMOS_SYSROOT_REPRO_SQLITE\n" .
			"  }else{\n" .
			"    memset(p, 0, n);\n" .
			"#endif\n" .
			"  }\n" .
			"  return p;\n" .
			"}\n";
		    s/\Q$old\E/$new/ or die;
		' "$gate_dir/usr/src/lib/libsqlite/src/util.c"
	fi

	if ! grep -Fq "$repro_tools_dir/sqlite2-normalize" \
		"$gate_dir/usr/src/cmd/svc/seed/Makefile"; then
		REPRO_SQLITE=$repro_tools_dir/sqlite2-normalize \
		REPRO_SQLITE_SOURCE=$repro_tools_dir/sqlite2-normalize.c \
		perl -0pi -e '
		    my $tools = "SVCCFG = ../svccfg/svccfg-native\n";
		    my $vars = $tools . "\n" .
			"REPRO_SQLITE =\t\t$ENV{REPRO_SQLITE}\n" .
			"REPRO_SQLITE_SOURCE =\t$ENV{REPRO_SQLITE_SOURCE}\n" .
			"REPRO_SQLITE_OBJECT =\t\$(ROOT)/lib/libsqlite-native.o\n";
		    s/\Q$tools\E/$vars/ or die;

		    my $configd = "\$(CONFIGD): FRC\n";
		    my $rule = "\$(REPRO_SQLITE): \$(CONFIGD) \$(REPRO_SQLITE_SOURCE)\n" .
			"\t\$(RM) \$@\n" .
			"\t\$(NATIVECC) \$(NATIVE_CFLAGS) -I\$(SRC)/lib/libsqlite " .
			"-o \$@ \$(REPRO_SQLITE_SOURCE) \$(REPRO_SQLITE_OBJECT)\n\n" .
			$configd;
		    s/\Q$configd\E/$rule/ or die;
		' "$gate_dir/usr/src/cmd/svc/seed/Makefile"

		if grep -Fq '$(IMPORT.mfst)' \
			"$gate_dir/usr/src/cmd/svc/seed/Makefile"; then
			perl -0pi -e '
			    for my $target (qw(global.db nonglobal.db miniroot.db)) {
				my $head = "$target: common.db";
				s/\Q$head\E/$head \$(REPRO_SQLITE)/ or die;
			    }
			    my $global = "\t\$(IMPORT.mfst) \$(GLOBAL_ZONE_DESCRIPTIONS)\n";
			    s/\Q$global\E/$global\t\$(REPRO_SQLITE) \$(SOURCE_DATE_EPOCH) \$@\n/ or die;
			    my $nonglobal = "\t\$(IMPORT.mfst) \$(NONGLOBAL_ZONE_DESCRIPTIONS)\n";
			    s/\Q$nonglobal\E/$nonglobal\t\$(REPRO_SQLITE) \$(SOURCE_DATE_EPOCH) \$@\n/ or die;
			    my $last = "\t    setprop config/local_only = true\n";
			    s/\Q$last\E/$last\t\$(REPRO_SQLITE) \$(SOURCE_DATE_EPOCH) \$@\n/ or die;
			' "$gate_dir/usr/src/cmd/svc/seed/Makefile"
		else
			perl -0pi -e '
			    for my $target (qw(global.db nonglobal.db miniroot.db)) {
				my $head = "$target: common.db";
				s/\Q$head\E/$head \$(REPRO_SQLITE)/ or die;
			    }
			    my $global_end = "\tdone\n\n" .
				"nonglobal.db:";
			    my $global_new = "\tdone\n" .
				"\t\$(REPRO_SQLITE) \$(SOURCE_DATE_EPOCH) global.db\n\n" .
				"nonglobal.db:";
			    s/\Q$global_end\E/$global_new/ or die;
			    my $nonglobal_end = "\tdone\n\n" .
				"miniroot.db:";
			    my $nonglobal_new = "\tdone\n" .
				"\t\$(REPRO_SQLITE) \$(SOURCE_DATE_EPOCH) nonglobal.db\n\n" .
				"miniroot.db:";
			    s/\Q$nonglobal_end\E/$nonglobal_new/ or die;
			    my $last = "\t\$(SVCCFG) -s svc:/network/rpc/bind " .
				"setprop config/local_only = true\n";
			    my $last_new = $last .
				"\t\$(REPRO_SQLITE) \$(SOURCE_DATE_EPOCH) miniroot.db\n";
			    s/\Q$last\E/$last_new/ or die;
			' "$gate_dir/usr/src/cmd/svc/seed/Makefile"
		fi
	fi

	if ! grep -q 'LC_ALL=C.*SORT' "$gate_dir/usr/src/lib/pyzfs/Makefile"; then
		perl -0pi -e '
		    my $old = "MSGFIND =\t\$(FIND) . -name '\''*.py'\'' -o -name '\''*.c'\''\n";
		    my $new = "MSGFIND =\t\$(FIND) . -name '\''*.py'\'' -o " .
			"-name '\''*.c'\'' | LC_ALL=C \$(SORT)\n";
		    s/\Q$old\E/$new/ or die;
		' "$gate_dir/usr/src/lib/pyzfs/Makefile"
	fi

	compileall_flags='-s $(ROOT)'
	if [ "$release" = 20181213 ]; then
		# r151030's Python predates compileall -s.  -d still replaces the
		# embedded source filename with a stable, checkout-independent value.
		compileall_flags='-d .'
	fi

	for makefile in \
		"$gate_dir/usr/src/lib/pyzfs/py3/Makefile" \
		"$gate_dir/usr/src/lib/pysolaris/py3/Makefile"; do
		if grep -Fq '$(PYTHON3) -mpy_compile $@' "$makefile"; then
			REPRO_COMPILEALL_FLAGS=$compileall_flags perl -0pi -e '
			    s{\$\(PYTHON3\) -mpy_compile \$@}
			      {\$(PYTHON3) -m compileall -q -f $ENV{REPRO_COMPILEALL_FLAGS} \$@} or die;
			' "$makefile"
		fi
		expected_compileall='$(PYTHON3) -m compileall -q -f '"$compileall_flags"' $@'
		grep -Fq "$expected_compileall" \
			"$makefile" || die "patching Python 3 bytecode rule in $makefile"
	done

	for makefile in \
		"$gate_dir/usr/src/lib/pyzfs/py3b/Makefile" \
		"$gate_dir/usr/src/lib/pysolaris/py3b/Makefile"; do
		[ -f "$makefile" ] || continue
		if grep -Fq '$(PYTHON3b) -mpy_compile $@' "$makefile"; then
			REPRO_COMPILEALL_FLAGS=$compileall_flags perl -0pi -e '
			    s{\$\(PYTHON3b\) -mpy_compile \$@}
			      {\$(PYTHON3b) -m compileall -q -f $ENV{REPRO_COMPILEALL_FLAGS} \$@} or die;
			' "$makefile"
		fi
		expected_compileall='$(PYTHON3b) -m compileall -q -f '"$compileall_flags"' $@'
		grep -Fq "$expected_compileall" \
			"$makefile" || die "patching Python 3b bytecode rule in $makefile"
	done

	if ! grep -Fq "$repro_tools_dir/pkgrepo" "$gate_dir/usr/src/pkg/Makefile"; then
		REPRO_PKGREPO=$repro_tools_dir/pkgrepo perl -0pi -e '
		    my $old = "\t\tpkgrepo refresh -s \$(PKGDEST)/repo.\$\$r; \\\n";
		    my $new = "\t\t$ENV{REPRO_PKGREPO} refresh " .
			"-s \$(PKGDEST)/repo.\$\$r; \\\n";
		    s/\Q$old\E/$new/ or die;
		' "$gate_dir/usr/src/pkg/Makefile"
	fi

	if ! grep -Fq "$repro_tools_dir/pkgdepend" "$gate_dir/usr/src/pkg/Makefile"; then
		REPRO_PKGDEPEND=$repro_tools_dir/pkgdepend perl -pi -e '
		    s{^\t\tpkgdepend -R }{\t\t$ENV{REPRO_PKGDEPEND} -R };
		    s{^\t\tpkgdepend generate }{\t\t$ENV{REPRO_PKGDEPEND} generate };
		' "$gate_dir/usr/src/pkg/Makefile"
		grep -Fq "$repro_tools_dir/pkgdepend -R" \
			"$gate_dir/usr/src/pkg/Makefile" || die "patching pkgdepend resolve"
		grep -Fq "$repro_tools_dir/pkgdepend generate" \
			"$gate_dir/usr/src/pkg/Makefile" || die "patching pkgdepend generate"
	fi

	if grep -Fq '$(PKGDEBUG)pkgsend -s file://$(@) create-repository' \
		"$gate_dir/usr/src/pkg/Makefile"; then
		REPRO_PKGSEND=$repro_tools_dir/pkgsend perl -0pi -e '
		    my $old = "\t\$(PKGDEBUG)pkgsend -s file://\$(@) create-repository \\\n";
		    my $new = "\t\$(PKGDEBUG)$ENV{REPRO_PKGSEND} " .
			"-s file://\$(@) create-repository \\\n";
		    s/\Q$old\E/$new/ or die;
		' "$gate_dir/usr/src/pkg/Makefile"
	fi

	if ! grep -Fq "$repro_tools_dir/jar" "$gate_dir/usr/src/Makefile.master"; then
		REPRO_JAR=$repro_tools_dir/jar perl -0pi -e '
		    my $needle = "JAR=\t\t\$(JAVA_ROOT)/bin/jar\n";
		    my $replace = "JAR=\t\t$ENV{REPRO_JAR}\n";
		    s/\Q$needle\E/$replace/ or die;
		' "$gate_dir/usr/src/Makefile.master"
	fi
}

run_nightly() {
	cd "$gate_dir"
	nightly=/opt/onbld/bin/nightly
	if [ -n "$source_date_epoch" ]; then
		nightly=$repro_tools_dir/nightly
	fi
	"$nightly" "./illumos.$release.sh" > "$workdir/nightly-$release.out" 2>&1
}

latest_mail_msg() {
	if [ -f "$gate_dir/log/mail_msg" ]; then
		printf '%s\n' "$gate_dir/log/mail_msg"
		return
	fi
	find "$gate_dir/log" -name mail_msg -type f | sort | tail -1
}

check_nightly_summary() {
	mail_msg=$(latest_mail_msg)
	[ -n "$mail_msg" ] && [ -f "$mail_msg" ] || die "nightly did not produce mail_msg"

	"$awk_cmd" '
		/^==== (Make clobber ERRORS|Make tools clobber ERRORS|Bootstrap build errors|Tools build errors|Build errors \(non-DEBUG\)|package build errors \(non-DEBUG\)) ====/ {
			section=$0
			next
		}
		/^==== / {
			section=""
			next
		}
		section != "" && NF {
			if (!bad) {
				print "nightly reported errors:" > "/dev/stderr"
			}
			print section > "/dev/stderr"
			print $0 > "/dev/stderr"
			bad=1
		}
		END { exit bad ? 1 : 0 }
	' "$mail_msg"

	repo=$gate_dir/packages/i386/nightly-nd/repo.redist
	[ -d "$repo/file" ] && [ -d "$repo/pkg" ] ||
		die "nightly did not produce a populated repo.redist at $repo"
}

build_archive() {
	repo=$gate_dir/packages/i386/nightly-nd/repo.redist
	mkdir -p "$output"
	cd "$repo_root"
	actual_cargo_lock_sha=$(sha256_file "$repo_root/mf2tar/Cargo.lock")
	[ "$actual_cargo_lock_sha" = "$mf2tar_cargo_lock_sha256" ] ||
		die "mf2tar Cargo.lock checksum mismatch: $actual_cargo_lock_sha"
	if command -v rustc >/dev/null 2>&1; then
		rustc_path=$(command -v rustc)
	else
		rustc_path=/opt/ooce/bin/rustc
	fi
	actual_rust_toolchain=$("$rustc_path" --version | "$awk_cmd" '{ print $2 }')
	[ "$actual_rust_toolchain" = "$mf2tar_rust_toolchain" ] ||
		die "mf2tar requires Rust $mf2tar_rust_toolchain; found $actual_rust_toolchain"
	gate_compiler_dir=$(dirname "$gate_cc")
	PATH=/opt/ooce/bin:$gate_compiler_dir:$PATH \
		gmake archive RELEASE="$release" OUTPUT="$output" ILLUMOS_PKGREPO="$repo"
}

verify_archive() {
	archive=$(find "$output" -name "illumos-sysroot-i386-$release-*.tar.gz" -type f |
		sort | tail -1)
	[ -n "$archive" ] || die "could not find built archive in $output"

	gzip -t "$archive"
	gzip -dc "$archive" | tar tf - > "$output/tar.list"
	entries=$(wc -l < "$output/tar.list" | tr -d ' ')

	if command -v digest >/dev/null 2>&1; then
		sha256=$(digest -a sha256 "$archive")
	else
		sha256=$(sha256sum "$archive" | "$awk_cmd" '{ print $1 }')
	fi

	cat > "$archive.sha256" <<EOF
$sha256  $(basename "$archive")
EOF

	printf 'archive=%s\n' "$archive"
	printf 'entries=%s\n' "$entries"
	printf 'sha256=%s\n' "$sha256"
}

check_builder_release
toolchain_dir=${OMNIOS_TOOLCHAIN_DIR:-}
if [ -n "$toolchain_dir" ]; then
	checked_lock=$repo_root/locks/toolchain.$release.lock
	kit_lock=$toolchain_dir/toolchain.$release.lock
	[ -f "$checked_lock" ] || die "missing checked-in toolchain lock: $checked_lock"
	[ -f "$kit_lock" ] || die "missing toolchain-kit lock: $kit_lock"
	cmp -s "$checked_lock" "$kit_lock" ||
		die "toolchain-kit lock does not match $checked_lock"
	if $install_deps; then
		"$repo_root/scripts/install-omnios-toolchain.sh" "$toolchain_dir"
	else
		"$repo_root/scripts/install-omnios-toolchain.sh" -v "$toolchain_dir"
	fi
else
	if [ "${ILLUMOS_SYSROOT_REQUIRE_LOCKED_TOOLCHAIN:-}" = 1 ]; then
		die "OMNIOS_TOOLCHAIN_DIR is required for this build"
	fi
	if $install_deps; then
		printf 'WARNING: installing development packages from live publishers\n' >&2
		install_omnios_deps
	fi
fi

check_tools
checkout_gate
check_gate_has_no_rust
prepare_closed_bins
prepare_repro_tools
prepare_env_file
apply_gate_repro_patches
if [ "${ILLUMOS_SYSROOT_PREPARE_ONLY:-}" = 1 ]; then
	exit 0
fi
run_nightly
check_nightly_summary
if [ "${ILLUMOS_SYSROOT_GATE_ONLY:-}" = 1 ]; then
	exit 0
fi
build_archive
verify_archive
