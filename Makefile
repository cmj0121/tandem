SUBDIR :=
ADDON  := Tandem
FLAVOR ?= _classic_beta_
MODE   ?= link

export FLAVOR

.PHONY: all clean test run build install uninstall upgrade help $(SUBDIR)

all: $(SUBDIR) 		# default action
	@[ -f .git/hooks/pre-commit ] || pre-commit install --install-hooks
	@git config commit.template .git-commit-template

clean: $(SUBDIR)	# clean-up environment
	@find . -name '*.sw[po]' -delete

test:				# syntax-check the Lua files and test wow-dir.sh
	luac -p $(ADDON)/*.lua
	scripts/wow-dir_test.sh

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

upgrade:			# upgrade all the necessary packages
	pre-commit autoupdate

help:				# show this message
	@printf "Usage: make [OPTION]\n"
	@printf "\n"
	@perl -nle 'print $$& if m{^[\w-]+:.*?#.*$$}' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?#"} {printf "    %-18s %s\n", $$1, $$2}'

$(SUBDIR):
	$(MAKE) -C $@ $(MAKECMDGOALS)
