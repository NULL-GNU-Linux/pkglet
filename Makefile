DESTDIR ?=
IS_ROOT := $(shell id -u 2>/dev/null)
ifeq ($(IS_ROOT),0)
PREFIX ?= $(DESTDIR)/usr
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib/pkglet
ETCDIR = $(DESTDIR)/etc/pkglet
CACHEDIR = $(DESTDIR)/var/cache/pkglet
else
PREFIX ?= $(DESTDIR)$(HOME)/.local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib/pkglet
ETCDIR = $(HOME)/.config/pkglet
CACHEDIR = $(HOME)/.cache/pkglet
endif
MODULES = $(shell find src -name '*.lua')
.PHONY: all install uninstall clean
all:
	@echo "this is pkglet lmao, no building step."

docs:
	rm -rf docs/Markdownium
	cd docs && git clone https://github.com/Markdownium/Markdownium
	cp docs/config.json docs/Markdownium/

install_docs:
	@mkdir -p $(PREFIX)/share/doc/pkglet/
	cp -r docs/* $(PREFIX)/share/doc/pkglet/

install:
	@rm -rf $(LIBDIR)
	@rm -f $(BINDIR)/pkglet
	install -Dm755 src/pkglet $(BINDIR)/pkglet
	ln -sf $(BINDIR)/pkglet $(BINDIR)/pkg
	ln -sf $(BINDIR)/pkglet $(BINDIR)/]
	ln -sf $(BINDIR)/pkglet $(BINDIR)/pl
	install -dm755 $(LIBDIR)
	$(foreach module,$(MODULES),install -Dm644 $(module) $(LIBDIR)/$(module);)
	install -dm755 $(ETCDIR)
	install -dm755 $(ETCDIR)/package.opts
	install -dm755 $(CACHEDIR)
	install -dm755 $(CACHEDIR)/build
	install -dm755 $(CACHEDIR)/distfiles
	install -dm755 $(CACHEDIR)/temp_install
	install -dm755 $(CACHEDIR)/repos
	@if [ ! -f $(ETCDIR)/repos.conf ]; then \
		echo "# pkglet repository configuration" > $(ETCDIR)/repos.conf; \
		echo "# Format: <name> <path>" >> $(ETCDIR)/repos.conf; \
		echo "# For git repositories, use URL:" >> $(ETCDIR)/repos.conf; \
		echo "# main https://github.com/user/repo.git" >> $(ETCDIR)/repos.conf; \
		echo "# Example:" >> $(ETCDIR)/repos.conf; \
		echo "# main /var/db/pkglet/repos/main" >> $(ETCDIR)/repos.conf; \
	fi
	@if [ ! -f $(ETCDIR)/make.lua ]; then \
		echo "-- pkglet build configuration" > $(ETCDIR)/make.lua; \
		echo "default_build_mode = \"binary\"" >> $(ETCDIR)/make.lua; \
		echo "MAKEOPTS = {" >> $(ETCDIR)/make.lua; \
		echo "    jobs = 8," >> $(ETCDIR)/make.lua; \
		echo "    load = 9," >> $(ETCDIR)/make.lua; \
		echo "    extra = \"\"" >> $(ETCDIR)/make.lua; \
		echo "}" >> $(ETCDIR)/make.lua; \
	fi
	@if [ ! -f $(ETCDIR)/package.mask ]; then \
		echo "# pkglet package mask" > $(ETCDIR)/package.mask; \
		echo "# One package per line" >> $(ETCDIR)/package.mask; \
	fi

uninstall:
	rm -f $(BINDIR)/pkglet
	rm -rf $(LIBDIR)
	@echo "Configuration files in $(ETCDIR) were not removed"

clean:
	@echo "Nothing to clean"
