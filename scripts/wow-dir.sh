#!/bin/sh
# Print the "World of Warcraft" directory that holds $FLAVOR/Interface/AddOns.
# Order: $WOW_DIR if set -> common roots -> Spotlight (mdfind).
set -eu

FLAVOR="${FLAVOR:-_classic_beta_}"

is_client() {
	[ -d "$1/$FLAVOR/Interface/AddOns" ]
}

if [ -n "${WOW_DIR:-}" ]; then
	if is_client "$WOW_DIR"; then
		printf '%s\n' "$WOW_DIR"
		exit 0
	fi
	printf 'error: WOW_DIR=%s has no %s/Interface/AddOns\n' "$WOW_DIR" "$FLAVOR" >&2
	exit 1
fi

for root in /Applications "$HOME/Applications" /Users/Shared; do
	if is_client "$root/World of Warcraft"; then
		printf '%s\n' "$root/World of Warcraft"
		exit 0
	fi
done

if command -v mdfind >/dev/null 2>&1; then
	found=$(mdfind 'kMDItemFSName == "World of Warcraft" && kMDItemContentType == "public.folder"' 2>/dev/null |
		while IFS= read -r dir; do
			if is_client "$dir"; then
				printf '%s\n' "$dir"
				break
			fi
		done)
	if [ -n "$found" ]; then
		printf '%s\n' "$found"
		exit 0
	fi
fi

cat >&2 <<EOF
error: no World of Warcraft client with $FLAVOR/Interface/AddOns found; searched:
  /Applications/World of Warcraft
  $HOME/Applications/World of Warcraft
  /Users/Shared/World of Warcraft
  Spotlight (mdfind) for folders named "World of Warcraft"
Set WOW_DIR to the "World of Warcraft" folder, or FLAVOR to another client flavor.
EOF
exit 1
