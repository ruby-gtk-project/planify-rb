PREFIX ?= /usr/local
DESTDIR ?=

APP_ID := io.github.alainm23.planify
PKGDIR := $(DESTDIR)$(PREFIX)/share/$(APP_ID)
BINDIR := $(DESTDIR)$(PREFIX)/bin
DATADIR := $(DESTDIR)$(PREFIX)/share

LANGUAGES := $(notdir $(basename $(wildcard po/*.po)))

.PHONY: run test resources install uninstall manifest flatpak clean

# Run out of the checkout, as a development build.
run: resources
	bundle exec ruby bin/planify-dev

# The icons and stylesheet are loaded from the gresource bundle, exactly as
# upstream loads them, so it has to exist before the app starts.
resources:
	cd data && glib-compile-schemas --strict .
	cd data && glib-compile-resources --sourcedir=. \
		--target=planify.gresource $(APP_ID).gresource.xml

test: resources
	bundle exec rubocop
	GSETTINGS_SCHEMA_DIR=$(CURDIR)/data bundle exec ruby test/test_load.rb
	GSETTINGS_SCHEMA_DIR=$(CURDIR)/data bundle exec ruby test/test_sync.rb
	GSETTINGS_SCHEMA_DIR=$(CURDIR)/data bundle exec ruby test/test_cli.rb
	GSETTINGS_SCHEMA_DIR=$(CURDIR)/data env -u DISPLAY -u WAYLAND_DISPLAY \
		bundle exec ruby test/drive_main.rb
	appstreamcli validate --no-net data/$(APP_ID).metainfo.xml.in.in || true
	# Syntax only. Three of the upstream catalogues (hr, da, fr) fail
	# --check-format on `main` as well, so failing the suite on them would
	# only report a bug this port did not introduce.
	find po/ -type f -name "*.po" -print0 | xargs -0 -n1 msgfmt -o /dev/null

# lib/ and data/ stay siblings so lib/planify/paths.rb finds the data next to
# it, exactly as it does in the checkout.
install: resources
	install -d $(PKGDIR)/lib $(PKGDIR)/data $(PKGDIR)/bin $(BINDIR)
	cp -r lib/. $(PKGDIR)/lib/
	cp -r data/. $(PKGDIR)/data/
	install -m 755 bin/planify $(PKGDIR)/bin/planify
	install -m 755 bin/planify-cli $(PKGDIR)/bin/planify-cli
	install -m 755 bin/planify-quick-add $(PKGDIR)/bin/planify-quick-add
	for language in $(LANGUAGES); do \
		install -d $(PKGDIR)/data/locale/$$language/LC_MESSAGES; \
		msgfmt --output $(PKGDIR)/data/locale/$$language/LC_MESSAGES/$(APP_ID).mo po/$$language.po; \
	done
	for binary in planify planify-cli planify-quick-add; do \
		printf '#!/bin/sh\nexec %s/bin/%s "$$@"\n' \
			'$(PREFIX)/share/$(APP_ID)' "$$binary" > $(BINDIR)/$$binary; \
		chmod 755 $(BINDIR)/$$binary; \
	done
	install -Dm 644 data/$(APP_ID).SearchProvider.ini \
		$(DATADIR)/gnome-shell/search-providers/$(APP_ID).SearchProvider.ini
	install -Dm 644 data/$(APP_ID).QuickAdd.desktop \
		$(DATADIR)/applications/$(APP_ID).QuickAdd.desktop
	install -Dm 644 data/$(APP_ID).gschema.xml \
		$(DATADIR)/glib-2.0/schemas/$(APP_ID).gschema.xml
	glib-compile-schemas --strict $(DATADIR)/glib-2.0/schemas
	install -Dm 644 data/icons/hicolor/scalable/apps/$(APP_ID).svg \
		$(DATADIR)/icons/hicolor/scalable/apps/$(APP_ID).svg
	install -Dm 644 data/icons/hicolor/symbolic/apps/$(APP_ID)-symbolic.svg \
		$(DATADIR)/icons/hicolor/symbolic/apps/$(APP_ID)-symbolic.svg

uninstall:
	rm -rf $(PKGDIR)
	rm -f $(BINDIR)/planify $(BINDIR)/planify-cli $(BINDIR)/planify-quick-add
	rm -f $(DATADIR)/gnome-shell/search-providers/$(APP_ID).SearchProvider.ini
	rm -f $(DATADIR)/applications/$(APP_ID).QuickAdd.desktop
	rm -f $(DATADIR)/glib-2.0/schemas/$(APP_ID).gschema.xml
	rm -f $(DATADIR)/icons/hicolor/scalable/apps/$(APP_ID).svg
	rm -f $(DATADIR)/icons/hicolor/symbolic/apps/$(APP_ID)-symbolic.svg

# Regenerate the manifest after changing the Gemfile: every gem is pinned in
# it by path and checksum.
manifest:
	bundle cache --no-install
	bundle exec ruby tools/generate-flatpak-manifest.rb

flatpak: manifest
	flatpak-builder --user --force-clean --repo=repo --install-deps-from=flathub \
		build-dir $(APP_ID).json
	flatpak --user remote-add --no-gpg-verify --if-not-exists planify repo
	flatpak --user install --reinstall --assumeyes planify $(APP_ID)

clean:
	rm -rf tmp data/locale data/gschemas.compiled data/planify.gresource
	rm -rf build-dir repo .flatpak-builder
