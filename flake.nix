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
            # `make test` validates the appstream and desktop metadata.
            appstream
            desktop-file-utils
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
          ];

          shellHook = ''
            export BUNDLE_PATH="$PWD/vendor/bundle"
            export BUNDLE_BUILD__GTK4="--use-system-libraries"
            # libecal and libedataserver have no Ruby gems; the calendar-event
            # service loads them straight from their typelibs, so both the
            # typelib and the shared library have to be findable.
            export GI_TYPELIB_PATH="${pkgs.gtk4}/lib/girepository-1.0:${pkgs.libadwaita}/lib/girepository-1.0:${pkgs.evolution-data-server}/lib/girepository-1.0''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
            export LD_LIBRARY_PATH="${pkgs.evolution-data-server}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          '';
        };
      }
    );
}
