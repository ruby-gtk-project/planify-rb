{
  description = "Ruby GTK4 development shell";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [ pkg-config wrapGAppsHook4 ];
          buildInputs = with pkgs; [
            ruby_3_4
            bundler
            bundix
            xvfb-run
            atk
            gtk4
            libadwaita
            gobject-introspection
            glib
            cairo
            pango
            gdk-pixbuf
            harfbuzz
            libyaml
            sqlite
            evolution-data-server
            # `make test` validates the appstream and desktop metadata, and
            # the `appstream` gem's AppStream typelib comes from this package
            # too.
            appstream
            desktop-file-utils
            gsettings-desktop-schemas
            adwaita-icon-theme

            # Typelibs for this app's binding gems (goa-rb, libspelling,
            # soup3). Everything comes from this one nixpkgs so GIO does not
            # register a type twice.
            gnome-online-accounts
            libspelling
            libsoup_3
            # The GIO TLS backend soup3 (and any other GIO-based HTTPS
            # client) needs at runtime; without it every https:// request
            # fails with "TLS support is not available".
            glib-networking
            gettext
            libxml2
            openssl

            # The ruby-gnome extconfs resolve Requires.private out of the .pc
            # files, so every private dependency of glib/cairo/pango/gtk needs
            # its own .pc here or the gem fails to configure.
            expat
            freetype
            fontconfig
            fribidi
            graphene
            lerc
            libdatrie
            libdeflate
            libepoxy
            libpng
            libpthread-stubs
            libselinux
            libsepol
            libsysprof-capture
            libthai
            libwebp
            libxkbcommon
            libX11
            libXau
            libxcb
            libXdmcp
            libXext
            libXrender
            pcre2
            pixman
            util-linux
            xz
            zstd

            rubyPackages_3_4.rspec
          ];

          shellHook = ''
            export BUNDLE_PATH="$PWD/vendor/bundle"
            export BUNDLE_BUILD__GTK4="--use-system-libraries"
            # libecal and libedataserver have no Ruby gems; the calendar-event
            # service loads them straight from their typelibs, so both the
            # typelib and the shared library have to be findable.
            export GI_TYPELIB_PATH="${pkgs.gtk4}/lib/girepository-1.0:${pkgs.libadwaita}/lib/girepository-1.0:${pkgs.evolution-data-server}/lib/girepository-1.0:${pkgs.appstream}/lib/girepository-1.0:${pkgs.gnome-online-accounts}/lib/girepository-1.0:${pkgs.libspelling}/lib/girepository-1.0:${pkgs.libsoup_3}/lib/girepository-1.0''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
            export LD_LIBRARY_PATH="${pkgs.evolution-data-server}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            # ashpd carries a Rust extension; its precompiled platform gem
            # needs no compiler and must not be swapped for the source gem.
            export BUNDLE_FORCE_RUBY_PLATFORM=false
            export GIO_EXTRA_MODULES="${pkgs.glib-networking}/lib/gio/modules''${GIO_EXTRA_MODULES:+:$GIO_EXTRA_MODULES}"
            # GTK's own built-in dialogs (the emoji chooser among them) load
            # their GSettings schema from here; without it a dialog that
            # touches one aborts the process rather than merely losing a
            # feature.
            export XDG_DATA_DIRS="${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}:${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.adwaita-icon-theme}/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
            # RUBYLIB is what makes the test/ scripts, which require_relative
            # into lib/, work from a checkout.
            export RUBYLIB="$PWD/lib''${RUBYLIB:+:$RUBYLIB}"
            # The repo-root Gemfile is kettle-jem's development bundle
            # (rubocop, rspec, yard, the kettle-dev stack); several of those
            # gems require a newer Ruby than this shell ships, so `bundle
            # install` against it fails version solving outright. nix/Gemfile
            # holds just the gemspec's runtime dependencies, already
            # installed into nix/vendor/bundle (checked in, built with
            # --use-system-libraries against this same nixpkgs), so point
            # Bundler there instead of at the root Gemfile.
            export BUNDLE_GEMFILE="$PWD/nix/Gemfile"
            export BUNDLE_PATH__SYSTEM="false"
            export BUNDLE_PATH="$PWD/nix/vendor/bundle"

            echo "planify devshell — ruby $(ruby -e 'print RUBY_VERSION')"
            echo "run the app:   nix develop --command xvfb-run -a bundle exec ruby bin/planify-dev"
            echo "drive the app: GSETTINGS_SCHEMA_DIR=\$PWD/data nix develop --command xvfb-run -a bundle exec ruby test/drive_main.rb"
            echo "run the specs: GSETTINGS_SCHEMA_DIR=\$PWD/data bundle exec ruby test/test_load.rb test/test_sync.rb test/test_cli.rb"
            echo "check it all:  make test"
          '';
        };
      }
    );
}
