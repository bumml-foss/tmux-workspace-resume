# ai-revive — lint, test, install and package. `make` prints this help.
# Install paths follow GNU conventions: `make install PREFIX=/usr DESTDIR=/tmp/stage`.
PREFIX  ?= /usr/local
DESTDIR ?=
UNITDIR ?= $(PREFIX)/lib/systemd/user
SHAREDIR = $(PREFIX)/share/ai-revive
MANDIR   = $(PREFIX)/share/man
VERSION := $(shell cat VERSION)

SH_FILES = ai-revive.tmux bin/ai-revive bin/byobu-ai-revive $(wildcard lib/*.sh) $(wildcard resumers/*) \
           tests/run-tests.sh $(wildcard tests/lib/*.sh) tests/fakes/claude $(wildcard tests/test-*.sh)

.DEFAULT_GOAL := help
.PHONY: help lint test install uninstall deb deb-docker deb-deps clean

help:
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

lint: ## shellcheck + bash -n over every script
	shellcheck -x $(SH_FILES)
	@for f in $(SH_FILES); do bash -n "$$f" || exit 1; done
	@grep -rqE 'default-(command|shell)' lib/enable.sh && { echo "lib/enable.sh must never contain the byobu trigger strings"; exit 1; } || true

test: ## run tests/test-*.sh on private tmux servers (never touches your byobu)
	tests/run-tests.sh

install: ## install under $(DESTDIR)$(PREFIX) (default /usr/local)
	install -d "$(DESTDIR)$(PREFIX)/bin" "$(DESTDIR)$(SHAREDIR)/lib" "$(DESTDIR)$(SHAREDIR)/resumers" \
	           "$(DESTDIR)$(SHAREDIR)/systemd/user" "$(DESTDIR)$(MANDIR)/man1" "$(DESTDIR)$(MANDIR)/man7" "$(DESTDIR)$(UNITDIR)"
	install -m 0755 bin/ai-revive bin/byobu-ai-revive "$(DESTDIR)$(PREFIX)/bin/"
	install -m 0755 ai-revive.tmux "$(DESTDIR)$(SHAREDIR)/"
	install -m 0644 VERSION "$(DESTDIR)$(SHAREDIR)/"
	install -m 0644 lib/*.sh "$(DESTDIR)$(SHAREDIR)/lib/"
	install -m 0755 resumers/* "$(DESTDIR)$(SHAREDIR)/resumers/"
	install -m 0644 systemd/user/* "$(DESTDIR)$(SHAREDIR)/systemd/user/"
	for u in systemd/user/*; do sed -E 's|^(Exec(Start\|Stop)=)[^ ]*ai-revive |\1$(PREFIX)/bin/ai-revive |' "$$u" > "$(DESTDIR)$(UNITDIR)/$$(basename "$$u")"; chmod 0644 "$(DESTDIR)$(UNITDIR)/$$(basename "$$u")"; done
	install -m 0644 man/ai-revive.1 man/byobu-ai-revive.1 "$(DESTDIR)$(MANDIR)/man1/"
	install -m 0644 man/ai-revive-resumers.7 "$(DESTDIR)$(MANDIR)/man7/"

uninstall: ## remove what install put under $(DESTDIR)$(PREFIX)
	rm -f "$(DESTDIR)$(PREFIX)/bin/ai-revive" "$(DESTDIR)$(PREFIX)/bin/byobu-ai-revive"
	rm -rf "$(DESTDIR)$(SHAREDIR)"
	rm -f "$(DESTDIR)$(UNITDIR)"/ai-revive-*.service "$(DESTDIR)$(UNITDIR)"/ai-revive-*.timer
	rm -f "$(DESTDIR)$(MANDIR)/man1/ai-revive.1" "$(DESTDIR)$(MANDIR)/man1/byobu-ai-revive.1" "$(DESTDIR)$(MANDIR)/man7/ai-revive-resumers.7"

deb-deps: ## apt install the packaging tool chain (needs sudo)
	sudo apt-get install -y build-essential devscripts debhelper lintian shellcheck

deb: ## build dist/ai-revive_$(VERSION)_all.deb locally (needs `make deb-deps`)
	@test "$$(dpkg-parsechangelog -S Version)" = "$(VERSION)" || { echo "VERSION ($(VERSION)) != debian/changelog ($$(dpkg-parsechangelog -S Version))"; exit 1; }
	dpkg-buildpackage -us -uc -b
	mkdir -p dist && mv ../ai-revive_$(VERSION)_all.deb ../ai-revive_$(VERSION)_*.buildinfo ../ai-revive_$(VERSION)_*.changes dist/
	lintian dist/ai-revive_$(VERSION)_all.deb

deb-docker: ## same as deb, inside ubuntu:24.04 (no local build deps needed)
	mkdir -p dist
	docker run --rm -v "$(CURDIR)":/src:ro -v "$(CURDIR)/dist":/out -e OWNER="$$(id -u):$$(id -g)" ubuntu:24.04 bash -euc '\
	  export DEBIAN_FRONTEND=noninteractive; \
	  apt-get update -qq && apt-get install -y -qq --no-install-recommends build-essential devscripts debhelper lintian >/dev/null; \
	  cp -a /src /build && cd /build && dpkg-buildpackage -us -uc -b && lintian ../ai-revive_*.deb; \
	  cp ../ai-revive_* /out/ && chown "$$OWNER" /out/ai-revive_*'
	ls -l dist/

clean: ## remove build artefacts
	rm -rf dist debian/ai-revive debian/.debhelper debian/debhelper-build-stamp debian/files debian/*.substvars debian/*.debhelper.log
