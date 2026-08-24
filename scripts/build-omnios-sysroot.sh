#!/bin/sh
#
# Build an illumos-gate IPS repo on OmniOS and assemble the sysroot archive
# from it.  This script is intended to run inside an OmniOS host or
# vmactions/omnios-vm.

set -eu

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
  GATE_COMMIT       illumos-gate commit; defaults from profiles/$RELEASE.mk
  GATE_BRANCH       local branch name (default: sysroot/$RELEASE)
  SOURCE_DATE_EPOCH reproducible build timestamp; defaults from profiles/$RELEASE.mk
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

workdir=${workdir:-$repo_root/.sysroot-omnios}
gate_dir=${gate_dir:-$workdir/illumos-gate}
output=${output:-$repo_root/output}
gate_repo=${GATE_REPO:-https://github.com/illumos/illumos-gate}
gate_commit=${GATE_COMMIT:-$(awk '$1 == "GATE_COMMIT" { print $3; exit }' "$profile")}
gate_branch=${GATE_BRANCH:-sysroot/$release}
source_date_epoch=${SOURCE_DATE_EPOCH:-$(awk '$1 == "SOURCE_DATE_EPOCH" { print $3; exit }' "$profile")}

[ -n "$gate_commit" ] || die "could not determine GATE_COMMIT from $profile"

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

install_omnios_deps() {
	run_as_root pkg set-publisher -g "https://pkg.omnios.org/r151046/extra" extra.omnios
	run_as_root pkg refresh --full
	run_as_root pkg install --accept \
		developer/build/onbld \
		developer/gcc10 \
		developer/build/gnu-make \
		developer/illumos-tools \
		runtime/java/openjdk11 \
		developer/versioning/git \
		ooce/developer/rust
}

check_tools() {
	for tool in git gmake gzip tar awk sed; do
		command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
	done
	if [ -n "$source_date_epoch" ]; then
		for tool in perl zip; do
			command -v "$tool" >/dev/null 2>&1 ||
				die "missing required reproducibility tool: $tool"
		done
	fi
	[ -x /opt/onbld/bin/nightly ] || die "missing /opt/onbld/bin/nightly"
	[ -x /opt/gcc-10/bin/gcc ] || die "missing /opt/gcc-10/bin/gcc"
	if ! command -v cargo >/dev/null 2>&1; then
		[ -x /opt/ooce/bin/cargo ] || die "missing cargo"
	fi
}

checkout_gate() {
	mkdir -p "$workdir"
	if [ ! -d "$gate_dir/.git" ]; then
		git init "$gate_dir"
		git -C "$gate_dir" remote add origin "$gate_repo"
	fi
	if ! git -C "$gate_dir" remote get-url origin >/dev/null 2>&1; then
		git -C "$gate_dir" remote add origin "$gate_repo"
	fi
	git -C "$gate_dir" fetch --depth 1 origin "$gate_commit"
	git -C "$gate_dir" checkout -B "$gate_branch" FETCH_HEAD
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
		cat >> "$gate_dir/illumos.$release.sh" <<EOF

# Reproducible sysroot build settings from $0
export SOURCE_DATE_EPOCH=$source_date_epoch
export ILLUMOS_SYSROOT_DTRACE_KEY=$source_date_epoch
export ILLUMOS_SYSROOT_DTRACE_SUFFIX=$dtrace_suffix
export DTRACE="$repro_tools_dir/dtrace -xnolibs"
export PKG_PUBLICATION_TIMESTAMP=$pkg_publication_timestamp
EOF
	fi
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
/usr/sbin/dtrace "$@"
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
		perl -0pi -e '
	    BEGIN {
	        $suffix = $ENV{"ILLUMOS_SYSROOT_DTRACE_SUFFIX"};
	        die "ILLUMOS_SYSROOT_DTRACE_SUFFIX must be seven digits\n"
	            unless defined($suffix) && $suffix =~ /^[0-9]{7}$/;
	    }
	    s/\$dtrace[0-9]{7}/\$dtrace$suffix/g;
		' "$@"
	fi
fi
EOF
	chmod +x "$repro_tools_dir/jar" "$repro_tools_dir/dtrace"
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
		perl -0pi -e '
		    my $fin = "\t\t    \$(<) \$(PM_FINAL_TRANSFORMS); \\\n";
		    my $ts = "\t\tif [ -n \"\$(PKG_PUBLICATION_TIMESTAMP)\" ]; then \\\n" .
			"\t\t\t\$(SED) -e \"/^set name=pkg.fmri value=/s/\$\$\/:\$(PKG_PUBLICATION_TIMESTAMP)\/\" \\\n" .
			"\t\t\t    \$(@) > \$(@).timestamped; \\\n" .
			"\t\t\t\$(MV) \$(@).timestamped \$(@); \\\n" .
			"\t\tfi; \\\n";
		    s/\Q$fin\E/$fin$ts/ or die;
		    my $pub = "\t\tpkgsend -s file://\$(PKGDEST)/repo.\$\$r publish \\\n";
		    my $pubts = "\t\tif [ -n \"\$(PKG_PUBLICATION_TIMESTAMP)\" ]; then \\\n" .
			"\t\t\tPKGSEND=\"pkgsend -D allow-timestamp\"; \\\n" .
			"\t\telse \\\n" .
			"\t\t\tPKGSEND=pkgsend; \\\n" .
			"\t\tfi; \\\n" .
			"\t\t\$\$PKGSEND -s file://\$(PKGDEST)/repo.\$\$r publish \\\n";
		    s/\Q$pub\E/$pubts/ or die;
		' "$gate_dir/usr/src/pkg/Makefile"
	fi

	if [ -x /usr/bin/gar ] &&
		! grep -q '^ARFLAGS[	 ]*=.*crD' "$gate_dir/usr/src/lib/ssp_ns/Makefile.com"; then
		perl -0pi -e '
		    my $needle = "include ../../Makefile.lib\n";
		    my $insert = "\nAR =\t\t/usr/bin/gar\nARFLAGS =\tcrD\n";
		    s/\Q$needle\E/$needle$insert/ or die;
		' "$gate_dir/usr/src/lib/ssp_ns/Makefile.com"
	fi

	repro_tools_dir=$workdir/repro-tools
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
	/opt/onbld/bin/nightly "./illumos.$release.sh" > "$workdir/nightly-$release.out" 2>&1
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

	awk '
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
	PATH=/opt/ooce/bin:/opt/gcc-10/bin:$PATH \
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
		sha256=$(sha256sum "$archive" | awk '{ print $1 }')
	fi

	cat > "$archive.sha256" <<EOF
$sha256  $(basename "$archive")
EOF

	printf 'archive=%s\n' "$archive"
	printf 'entries=%s\n' "$entries"
	printf 'sha256=%s\n' "$sha256"
}

if $install_deps; then
	install_omnios_deps
fi

check_tools
checkout_gate
prepare_repro_tools
prepare_env_file
apply_gate_repro_patches
run_nightly
check_nightly_summary
build_archive
verify_archive
