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
mkdir -p "$client/_forever_/Interface/AddOns"

out=$(WOW_DIR="$client" "$here/wow-dir.sh" 2>/dev/null)
check "explicit WOW_DIR with spaces is printed" "$out" "$client"

beta="$tmp/Beta/World of Warcraft"
mkdir -p "$beta/_classic_beta_/Interface/AddOns"
env -u FLAVOR WOW_DIR="$beta" "$here/wow-dir.sh" >/dev/null 2>&1
check "the default flavor is _forever_" "$?" "1"
out=$(WOW_DIR="$beta" FLAVOR=_classic_beta_ "$here/wow-dir.sh" 2>/dev/null)
check "FLAVOR=_classic_beta_ finds the beta client" "$out" "$beta"

env -u FLAVOR make -s -C "$here/.." install WOW_DIR="$client" >/dev/null 2>&1
check "make install links into _forever_ by default" "$(readlink "$client/_forever_/Interface/AddOns/Tandem")" \
	"$(cd "$here/.." && pwd)/Tandem"
env -u FLAVOR make -s -C "$here/.." uninstall WOW_DIR="$client" >/dev/null 2>&1
[ -e "$client/_forever_/Interface/AddOns/Tandem" ] || [ -L "$client/_forever_/Interface/AddOns/Tandem" ]
check "make uninstall removes it from _forever_ by default" "$?" "1"
make -s -C "$here/.." install WOW_DIR="$beta" FLAVOR=_classic_beta_ >/dev/null 2>&1
check "make install FLAVOR=_classic_beta_ links into the beta client" \
	"$(readlink "$beta/_classic_beta_/Interface/AddOns/Tandem")" "$(cd "$here/.." && pwd)/Tandem"

WOW_DIR="$tmp/missing" "$here/wow-dir.sh" >/dev/null 2>&1
check "invalid explicit WOW_DIR fails" "$?" "1"

FLAVOR=_no_such_flavor_ "$here/wow-dir.sh" >/dev/null 2>"$tmp/err"
check "no client found fails" "$?" "1"
grep -q 'searched' "$tmp/err"
check "no client found lists what was searched" "$?" "0"

[ "$fails" -eq 0 ]
