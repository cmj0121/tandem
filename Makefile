SUBDIR :=
ADDON  := Tandem
FLAVOR ?= _classic_beta_
MODE   ?= link
DATA   ?= data
OUT    ?= $(ADDON)/Data/Loot.lua

export FLAVOR

.PHONY: all clean test run build install uninstall import upgrade help $(SUBDIR)

all: $(SUBDIR) 		# default action
	@[ -f .git/hooks/pre-commit ] || pre-commit install --install-hooks
	@git config commit.template .git-commit-template

clean: $(SUBDIR)	# clean-up environment
	@find . -name '*.sw[po]' -delete

test:				# syntax-check the Lua files, test the addon, wow-dir.sh and the importer
	luac -p $$(find $(ADDON) scripts -name '*.lua')
	lua scripts/addon_test.lua
	scripts/wow-dir_test.sh
	scripts/import_test.sh

run:				# run in the local environment

build:				# build the binary/library

install:			# link the addon into the WoW client (MODE=copy to copy, WOW_DIR=... to override)
	@wow=$$(scripts/wow-dir.sh) && \
	dest="$$wow/$(FLAVOR)/Interface/AddOns/$(ADDON)" && \
	src="$(CURDIR)/$(ADDON)" && \
	echo "WoW client: $$wow" && \
	if [ "$(MODE)" = copy ]; then \
		if [ -L "$$dest" ]; then rm "$$dest"; fi && \
		mkdir -p "$$dest" && cp -R "$$src/." "$$dest/" && \
		echo "copied $$src -> $$dest"; \
	elif [ -L "$$dest" ] && [ "$$(readlink "$$dest")" = "$$src" ]; then \
		echo "already linked: $$dest -> $$src"; \
	elif [ -e "$$dest" ] && [ ! -L "$$dest" ]; then \
		echo "error: $$dest exists and is not a symlink; run 'make uninstall MODE=copy' first" >&2; exit 1; \
	else \
		ln -sfn "$$src" "$$dest" && echo "linked $$dest -> $$src"; \
	fi

uninstall:			# remove the installed addon (only a symlink, unless MODE=copy)
	@wow=$$(scripts/wow-dir.sh) && \
	dest="$$wow/$(FLAVOR)/Interface/AddOns/$(ADDON)" && \
	if [ -L "$$dest" ]; then \
		rm "$$dest" && echo "removed $$dest"; \
	elif [ -d "$$dest" ] && [ "$(MODE)" = copy ]; then \
		rm -rf "$$dest" && echo "removed $$dest"; \
	elif [ -e "$$dest" ]; then \
		echo "error: $$dest is not a symlink; use 'make uninstall MODE=copy' to remove a copy" >&2; exit 1; \
	else \
		echo "not installed: $$dest"; \
	fi

import:				# import every account's data into data/contributions and Tandem/Data/Loot.lua (WOW_DIR=, DATA=, OUT= to override)
	@wow=$$(scripts/wow-dir.sh) && \
	wtf="$$wow/$(FLAVOR)/WTF" && \
	locale=$$(sed -n 's/^SET textLocale "\([A-Za-z]*\)".*/\1/p' "$$wtf/Config.wtf" 2>/dev/null | head -n 1) && \
	locale=$${locale:-enUS} && \
	set -- && \
	for sv in "$$wtf"/Account/*/SavedVariables/Tandem.lua; do \
		[ -f "$$sv" ] || continue; \
		account=$$(basename "$$(dirname "$$(dirname "$$sv")")"); \
		id=$$(printf %s "$$account" | shasum -a 256 | cut -c1-12); \
		set -- "$$@" "$$locale" "$$id" "$$sv"; \
	done && \
	if [ $$# -eq 0 ]; then \
		echo "error: no $$wtf/Account/*/SavedVariables/Tandem.lua; log out or /reload in game first" >&2; exit 1; \
	fi && \
	lua scripts/import.lua "$(DATA)" "$(OUT)" "$$@"

upgrade:			# upgrade all the necessary packages
	pre-commit autoupdate

help:				# show this message
	@printf "Usage: make [OPTION]\n"
	@printf "\n"
	@perl -nle 'print $$& if m{^[\w-]+:.*?#.*$$}' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?#"} {printf "    %-18s %s\n", $$1, $$2}'

$(SUBDIR):
	$(MAKE) -C $@ $(MAKECMDGOALS)
