# tmux-workspace-resume — lint, test, install and package. `make` prints this help.
# Install paths follow GNU conventions: `make install PREFIX=/usr DESTDIR=/tmp/stage`.
PREFIX  ?= /usr/local
DESTDIR ?=
UNITDIR ?= $(PREFIX)/lib/systemd/user
SHAREDIR = $(PREFIX)/share/tmux-workspace-resume
MANDIR   = $(PREFIX)/share/man
VERSION := $(shell cat VERSION)

SH_FILES = tmux-workspace-resume.tmux bin/tmux-workspace-resume bin/byobu-tmux-workspace-resume $(wildcard lib/*.sh) $(wildcard resumers/*) \
           tests/run-tests.sh $(wildcard tests/lib/*.sh) $(wildcard tests/fakes/*) $(wildcard tests/test-*.sh) \
           $(wildcard scripts/*.sh)

.DEFAULT_GOAL := help
.PHONY: help lint test audit install uninstall deb deb-docker deb-deps clean

help:
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

lint: ## shellcheck + bash -n over every script
	shellcheck -x $(SH_FILES)
	@for f in $(SH_FILES); do bash -n "$$f" || exit 1; done
	@grep -rqE 'default-(command|shell)' lib/enable.sh && { echo "lib/enable.sh must never contain the byobu trigger strings"; exit 1; } || true

test: ## run tests/test-*.sh on private tmux servers (never touches your byobu)
	tests/run-tests.sh

audit: ## privacy audit of the whole history (secrets, e-mails, paths, hosts, real session ids)
	scripts/audit.sh

install: ## install under $(DESTDIR)$(PREFIX) (default /usr/local)
	install -d "$(DESTDIR)$(PREFIX)/bin" "$(DESTDIR)$(SHAREDIR)/lib" "$(DESTDIR)$(SHAREDIR)/resumers" \
	           "$(DESTDIR)$(SHAREDIR)/systemd/user" "$(DESTDIR)$(MANDIR)/man1" "$(DESTDIR)$(MANDIR)/man7" "$(DESTDIR)$(UNITDIR)"
	install -m 0755 bin/tmux-workspace-resume bin/byobu-tmux-workspace-resume "$(DESTDIR)$(PREFIX)/bin/"
	install -m 0755 tmux-workspace-resume.tmux "$(DESTDIR)$(SHAREDIR)/"
	install -m 0644 VERSION "$(DESTDIR)$(SHAREDIR)/"
	install -m 0644 lib/*.sh "$(DESTDIR)$(SHAREDIR)/lib/"
	install -m 0755 resumers/* "$(DESTDIR)$(SHAREDIR)/resumers/"
	install -m 0644 systemd/user/* "$(DESTDIR)$(SHAREDIR)/systemd/user/"
	for u in systemd/user/*; do sed -E 's|^(Exec(Start\|Stop)=)[^ ]*tmux-workspace-resume |\1$(PREFIX)/bin/tmux-workspace-resume |' "$$u" > "$(DESTDIR)$(UNITDIR)/$$(basename "$$u")"; chmod 0644 "$(DESTDIR)$(UNITDIR)/$$(basename "$$u")"; done
	install -m 0644 man/tmux-workspace-resume.1 man/byobu-tmux-workspace-resume.1 "$(DESTDIR)$(MANDIR)/man1/"
	install -m 0644 man/tmux-workspace-resume-resumers.7 "$(DESTDIR)$(MANDIR)/man7/"

uninstall: ## remove what install put under $(DESTDIR)$(PREFIX)
	rm -f "$(DESTDIR)$(PREFIX)/bin/tmux-workspace-resume" "$(DESTDIR)$(PREFIX)/bin/byobu-tmux-workspace-resume"
	rm -rf "$(DESTDIR)$(SHAREDIR)"
	rm -f "$(DESTDIR)$(UNITDIR)"/tmux-workspace-resume-*.service "$(DESTDIR)$(UNITDIR)"/tmux-workspace-resume-*.timer
	rm -f "$(DESTDIR)$(MANDIR)/man1/tmux-workspace-resume.1" "$(DESTDIR)$(MANDIR)/man1/byobu-tmux-workspace-resume.1" "$(DESTDIR)$(MANDIR)/man7/tmux-workspace-resume-resumers.7"

deb-deps: ## apt install the packaging tool chain (needs sudo)
	sudo apt-get install -y build-essential devscripts debhelper lintian shellcheck

deb: ## build dist/tmux-workspace-resume_$(VERSION)_all.deb locally (needs `make deb-deps`)
	@test "$$(dpkg-parsechangelog -S Version)" = "$(VERSION)" || { echo "VERSION ($(VERSION)) != debian/changelog ($$(dpkg-parsechangelog -S Version))"; exit 1; }
	dpkg-buildpackage -us -uc -b
	mkdir -p dist && mv ../tmux-workspace-resume_$(VERSION)_all.deb ../tmux-workspace-resume_$(VERSION)_*.buildinfo ../tmux-workspace-resume_$(VERSION)_*.changes dist/
	lintian dist/tmux-workspace-resume_$(VERSION)_all.deb

deb-docker: ## same as deb, inside ubuntu:24.04 (no local build deps needed)
	mkdir -p dist
	docker run --rm -v "$(CURDIR)":/src:ro -v "$(CURDIR)/dist":/out -e OWNER="$$(id -u):$$(id -g)" ubuntu:24.04 bash -euc '\
	  export DEBIAN_FRONTEND=noninteractive; \
	  apt-get update -qq && apt-get install -y -qq --no-install-recommends build-essential devscripts debhelper lintian >/dev/null; \
	  cp -a /src /build && cd /build && dpkg-buildpackage -us -uc -b && lintian ../tmux-workspace-resume_*.deb; \
	  cp ../tmux-workspace-resume_* /out/ && chown "$$OWNER" /out/tmux-workspace-resume_*'
	ls -l dist/

clean: ## remove build artefacts
	rm -rf dist debian/tmux-workspace-resume debian/.debhelper debian/debhelper-build-stamp debian/files debian/*.substvars debian/*.debhelper.log
