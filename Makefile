DESTDIR ?=
PREFIX ?= $(DESTDIR)/usr
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib/pkglet
ETCDIR = /etc/pkglet
MODULES = $(shell find src -name '*.lua')
.PHONY: all install uninstall clean
all:
	@echo "this is pkglet lmao, no building step."

docs:
	@echo "Generating documentation..."
	ldoc .

install_docs:
	@echo "Installing documentation..."
	install -Dm644 docs/* $(DESTDIR)$(PREFIX)/share/doc/pkglet/

install:
	@echo "Installing pkglet..."
	install -Dm755 src/pkglet $(DESTDIR)$(BINDIR)/pkglet
	install -dm755 $(DESTDIR)$(LIBDIR)
	$(foreach module,$(MODULES),install -Dm644 $(module) $(DESTDIR)$(LIBDIR)/$(module);)
	install -dm755 $(DESTDIR)$(ETCDIR)
	install -dm755 $(DESTDIR)$(ETCDIR)/package.opts
	@echo "Creating default config files..."
	@if [ ! -f $(DESTDIR)$(ETCDIR)/repos.conf ]; then \
		echo "# pkglet repository configuration" > $(DESTDIR)$(ETCDIR)/repos.conf; \
		echo "# Format: <name> <path>" >> $(DESTDIR)$(ETCDIR)/repos.conf; \
		echo "# Example:" >> $(DESTDIR)$(ETCDIR)/repos.conf; \
		echo "# main /var/db/pkglet/repos/main" >> $(DESTDIR)$(ETCDIR)/repos.conf; \
	fi
	@if [ ! -f $(DESTDIR)$(ETCDIR)/make.lua ]; then \
		echo "-- pkglet build configuration" > $(DESTDIR)$(ETCDIR)/make.lua; \
		echo "MAKEOPTS = {" >> $(DESTDIR)$(ETCDIR)/make.lua; \
		echo "    jobs = 8," >> $(DESTDIR)$(ETCDIR)/make.lua; \
		echo "    load = 9," >> $(DESTDIR)$(ETCDIR)/make.lua; \
		echo "    extra = \"\"" >> $(DESTDIR)$(ETCDIR)/make.lua; \
		echo "}" >> $(DESTDIR)$(ETCDIR)/make.lua; \
	fi
	@if [ ! -f $(DESTDIR)$(ETCDIR)/package.mask ]; then \
		echo "# pkglet package mask" > $(DESTDIR)$(ETCDIR)/package.mask; \
		echo "# One package per line" >> $(DESTDIR)$(ETCDIR)/package.mask; \
	fi
	@echo "Installation complete!"

uninstall:
	@echo "Uninstalling pkglet..."
	rm -f $(DESTDIR)$(BINDIR)/pkglet
	rm -rf $(DESTDIR)$(LIBDIR)
	@echo "Configuration files in $(ETCDIR) were not removed"
	@echo "Uninstall complete!"

clean:
	@echo "Nothing to clean"
