#!/bin/sh
#
# Resolve the exact package dependency closure from an installed OmniOS image.
# This deliberately follows the installed choice for require-any and other
# flexible dependencies instead of asking a live publisher to solve them.

set -eu

LC_ALL=C
LANG=C
export LC_ALL LANG

awk_cmd=awk
if command -v nawk >/dev/null 2>&1; then
	awk_cmd=nawk
fi

usage() {
	cat >&2 <<'EOF'
usage: scripts/capture-installed-package-closure.sh REQUESTED_FMRIS OUT

REQUESTED_FMRIS contains one exact installed FMRI per line.  OUT receives the
sorted exact installed closure.  Publishers are not contacted.
EOF
}

die() {
	echo "ERROR: $*" >&2
	exit 1
}

[ "$#" -eq 2 ] || {
	usage
	exit 2
}

requested=$1
out=$2
[ -s "$requested" ] || die "missing or empty requested FMRI set: $requested"

tmp_base=${TMPDIR:-/tmp}/illumos-sysroot-installed-closure.$$
installed=$tmp_base.installed
actions=$tmp_base.actions
input=$tmp_base.input
resolved=$tmp_base.resolved
requested_actual=$tmp_base.requested
trap 'rm -f "$installed" "$actions" "$input" "$resolved" "$requested_actual"' \
	EXIT HUP INT TERM

requested_args=$(cat "$requested")
# Exact FMRIs are passed as patterns so a different installed version cannot
# silently seed the dependency graph.
# shellcheck disable=SC2086
pkg list -Hv $requested_args | "$awk_cmd" '{ print $1 }' | LC_ALL=C sort \
	> "$requested_actual"
diff -u "$requested" "$requested_actual" ||
	die "requested FMRI set does not match the installed builder"

pkg list -Hv > "$installed"
pkg contents -H -t depend -o pkg.name,action.raw '*' > "$actions"
{
	"$awk_cmd" '{ print "M\t" $0 }' "$installed"
	"$awk_cmd" '{ print "D\t" $0 }' "$actions"
	"$awk_cmd" '{ print "R\t" $0 }' "$requested"
} > "$input"

"$awk_cmd" -F '\t' '
	function package_name(fmri, value) {
		value=fmri
		gsub(/[\[\],\047\"]/, "", value)
		sub(/^(fmri|predicate)=/, "", value)
		if (index(value, "pkg://") == 1) {
			value=substr(value, 7)
			value=substr(value, index(value, "/") + 1)
		} else if (index(value, "pkg:/") == 1) {
			value=substr(value, 6)
		}
		sub(/@.*/, "", value)
		return value
	}
	$1 == "M" {
		exact=$2
		sub(/ .*/, "", exact)
		name=package_name(exact)
		installed[name]=exact
		next
	}
	$1 == "D" {
		owner=$2
		raw=$3
		is_require=(raw ~ /type=require/)
		is_conditional=(raw ~ /type=conditional/)
		if (!is_require && !is_conditional)
			next
		count=split(raw, fields, " ")
		if (is_conditional) {
			predicate=""
			for (i=1; i <= count; i++) {
				if (fields[i] ~ /^predicate=/)
					predicate=package_name(fields[i])
			}
			if (predicate == "" || !(predicate in installed))
				next
		}
		for (i=1; i <= count; i++) {
			if (fields[i] !~ /^fmri=/)
				continue
			dependency=package_name(fields[i])
			if (dependency != "")
				edge[owner SUBSEP dependency]=1
		}
		next
	}
	$1 == "R" {
		requested_name=package_name($2)
		chosen[requested_name]=1
	}
	END {
		do {
			changed=0
			for (pair in edge) {
				split(pair, names, SUBSEP)
				if (chosen[names[1]] &&
				    names[2] in installed && !chosen[names[2]]) {
					chosen[names[2]]=1
					changed=1
				}
			}
		} while (changed)
		for (name in chosen) {
			if (!chosen[name])
				continue
			if (name in installed)
				print installed[name]
			else {
				missing[name]=1
				missing_count++
			}
		}
		for (name in missing)
			print "ERROR: requested package is not installed: " name > "/dev/stderr"
		if (missing_count != 0)
			exit 1
	}
' "$input" > "$resolved"
LC_ALL=C sort -u "$resolved" > "$out"
printf 'captured %s exact installed package FMRIs in %s\n' \
	"$(wc -l < "$out" | tr -d ' ')" "$out"
