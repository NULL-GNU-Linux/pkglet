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
	install -Dm644 docs/* $(PREFIX)/share/doc/pkglet/

install:
	@echo "Installing pkglet..."
	@rm -rf $(LIBDIR)
	@rm -rf $(BINDIR)/pkglet
	install -Dm755 src/pkglet $(BINDIR)/pkglet
	ln -s $(BINDIR)/pkglet $(BINDIR)/]
	install -dm755 $(LIBDIR)
	$(foreach module,$(MODULES),install -Dm644 $(module) $(LIBDIR)/$(module);)
	install -dm755 $(ETCDIR)
	install -dm755 $(ETCDIR)/package.opts
	@echo "Creating default config files..."
	@if [ ! -f $(ETCDIR)/repos.conf ]; then \
		echo "# pkglet repository configuration" > $(ETCDIR)/repos.conf; \
		echo "# Format: <name> <path>" >> $(ETCDIR)/repos.conf; \
		echo "# Example:" >> $(ETCDIR)/repos.conf; \
		echo "# main /var/db/pkglet/repos/main" >> $(ETCDIR)/repos.conf; \
	fi
	@if [ ! -f $(ETCDIR)/make.lua ]; then \
		echo "-- pkglet build configuration" > $(ETCDIR)/make.lua; \
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
	@echo "Installation complete!"

uninstall:
	@echo "Uninstalling pkglet..."
	rm -f $(BINDIR)/pkglet
	rm -rf $(LIBDIR)
	@echo "Configuration files in $(ETCDIR) were not removed"
	@echo "Uninstall complete!"

clean:
	@echo "Nothing to clean"
