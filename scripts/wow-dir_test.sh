#!/bin/sh
# Tests for wow-dir.sh using throwaway client trees whose paths contain spaces.
set -u

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

check() {
	if [ "$2" = "$3" ]; then
		printf 'ok   %s\n' "$1"
	else
		printf 'FAIL %s\n     want: %s\n     got:  %s\n' "$1" "$3" "$2"
		fails=$((fails + 1))
	fi
}

client="$tmp/World of Warcraft"
mkdir -p "$client/_classic_beta_/Interface/AddOns"

out=$(WOW_DIR="$client" "$here/wow-dir.sh" 2>/dev/null)
check "explicit WOW_DIR with spaces is printed" "$out" "$client"

WOW_DIR="$tmp/missing" "$here/wow-dir.sh" >/dev/null 2>&1
check "invalid explicit WOW_DIR fails" "$?" "1"

FLAVOR=_no_such_flavor_ "$here/wow-dir.sh" >/dev/null 2>"$tmp/err"
check "no client found fails" "$?" "1"
grep -q 'searched' "$tmp/err"
check "no client found lists what was searched" "$?" "0"

[ "$fails" -eq 0 ]
