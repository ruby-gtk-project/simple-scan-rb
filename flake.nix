{
  description = "simple-scan — a Ruby GTK4 port";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Scanner.scan is not a GObject-introspection binding — SANE has none
        # — so lib/sane_api.rb talks to libsane.so.1 directly via the `ffi`
        # gem. This is the library it dlopen's and the directory whose
        # libsane-*.so backends it then loads.
        saneBackends = pkgs.sane-backends;

        # The dev shell and the drive/spec scripts have no real scanner
        # attached, so SANE's own "test" backend stands in for one — it is
        # the virtual-scanner backend sane-backends ships for exactly this.
        # SANE_CONFIG_DIR replaces the default /etc/sane.d search path
        # wholesale, so this is the dll.conf that enables just "test", plus a
        # test.conf asking the backend for two virtual devices (test:0,
        # test:1) instead of its single-device default — otherwise nothing
        # in the drive script could exercise Scanner's multi-device list
        # (device_weight sorting, the status page's device dropdown with
        # more than one entry) at all.
        saneTestConfig = pkgs.runCommand "sane-test-config" { } ''
          mkdir -p $out/etc/sane.d
          echo "test" > $out/etc/sane.d/dll.conf
          echo "number_of_devices 2" > $out/etc/sane.d/test.conf
        '';

        # Shared libraries every ruby-gnome extension links against.
        gtkStack = with pkgs; [
          glib
          gobject-introspection
          cairo
          pango
          gdk-pixbuf
          graphene
          atk
          gtk4
          libadwaita
          harfbuzz
          librsvg
          # Carrying the typelibs for this app's binding gems. gtkStack feeds
          # both buildInputs and typelibPath, so one list does both jobs.
          packagekit
        ]
        # The Ruby `pkg-config` gem resolves `Requires.private` transitively and
        # hard-fails if any .pc in the chain is missing, so gtk4's whole private
        # closure has to be on PKG_CONFIG_PATH, not just its public deps.
        ++ (with pkgs; [
          fontconfig
          freetype
          libepoxy
          libpng
          libxkbcommon
          pcre2
          util-linux
          wayland
          zlib
          fribidi
          libdatrie
          libthai
          libselinux
          libsepol
          expat
          brotli
          bzip2
          graphite2
          icu
          libffi
          libxml2
          lerc
          libdeflate
          xz
          zstd
        ])
        # Un-prefixed names: the `xorg.*` package set is deprecated.
        ++ (with pkgs; [
          libx11
          libxau
          libxcursor
          libxdmcp
          libxext
          libxfixes
          libxi
          libxinerama
          libxrandr
          libxrender
          libxcb
          xorgproto
        ]);

        # ruby-gnome gems build C extensions with extconf.rb + the pkg-config
        # gem; nixpkgs only ships gemConfig entries for the GTK3-era subset, so
        # the GTK4 gems get their build inputs declared here.
        rubyGnomeGem = _attrs: {
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = gtkStack;
        };

        gemConfig = pkgs.defaultGemConfig // {
          gdk4 = rubyGnomeGem;
          gsk4 = rubyGnomeGem;
          gtk4 = rubyGnomeGem;
          graphene1 = rubyGnomeGem;
          adwaita = rubyGnomeGem;
          rsvg2 = rubyGnomeGem;
        };

        # `makeSearchPath` would take each package's *first* output, and glib's
        # first output is `bin`, which carries no typelibs — hence the explicit
        # `.out`. at-spi2-core is here for the Atk typelib.
        typelibPath = pkgs.lib.makeSearchPath "lib/girepository-1.0"
          (map (drv: drv.out or drv) (gtkStack ++ [ pkgs.at-spi2-core ]));

        # nix/ and not the repo root: the root Gemfile is kettle-jem's
        # development bundle — rubocop, rspec, yard, the kettle-dev stack — and
        # must not end up in a packaged app's runtime closure. nix/Gemfile holds
        # the gemspec's runtime dependencies only.
        gems = pkgs.bundlerEnv {
          name = "simple-scan-gems";
          ruby = pkgs.ruby_3_4;
          inherit gemConfig;
          gemdir = ./nix;
        };

        # The launcher is whatever the gemspec installs into exe/. Reading the
        # directory keeps this flake generic: no name to keep in step by hand.
        launcher = builtins.head (builtins.attrNames (builtins.readDir ./exe));

        # Optional directories: a port that has not grown translations or data
        # assets yet simply has none.
        optionalDirs = builtins.filter (d: builtins.pathExists (./. + "/${d}")) [
          "data"
          "po"
          "help"
        ];
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "simple-scan";
          version = "0.1.0";
          src = ./.;

          # Deliberately no wrapGAppsHook4: glib's setup hook relocates
          # share/glib-2.0/schemas during fixup, after wrapGAppsHook4 has
          # computed its wrapper arguments, so a schema would end up somewhere
          # the wrapper never looks. The wrapper below is built by hand and
          # points at both the pre- and post-move paths.
          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = [ gems saneBackends ] ++ gtkStack;

          dontBuild = true;

          installPhase = ''
            runHook preInstall

            mkdir -p $out/share/simple-scan
            cp -r lib $out/share/simple-scan/
            for d in ${pkgs.lib.escapeShellArgs optionalDirs}; do
              cp -r "$d" $out/share/simple-scan/
            done
            # exe/ sits next to lib/ so the launcher's `require "simple-scan"`
            # resolves against the copied tree.
            install -Dm755 exe/${launcher} $out/share/simple-scan/exe/${launcher}

            # Compile any GSettings schema the port ships.
            if [ -d data/schemas ]; then
              mkdir -p $out/share/glib-2.0/schemas
              cp data/schemas/*.gschema.xml $out/share/glib-2.0/schemas/
              ${pkgs.glib.dev}/bin/glib-compile-schemas $out/share/glib-2.0/schemas
            fi

            # app.help's `Gtk.show_uri("help:simple-scan", ...)` resolves
            # through yelp, which looks for Mallard pages under
            # share/help/<lang>/<app-name>/ on XDG_DATA_DIRS.
            if [ -d help ]; then
              mkdir -p $out/share/help
              for lang in help/*/; do
                lang=$(basename "$lang")
                [ -d "help/$lang" ] || continue
                mkdir -p "$out/share/help/$lang/simple-scan"
                cp -r "help/$lang"/* "$out/share/help/$lang/simple-scan/"
              done
            fi

            # The man page matching upstream's data/simple-scan.1.
            if [ -f data/simple-scan.1 ]; then
              install -Dm644 data/simple-scan.1 $out/share/man/man1/${launcher}.1
            fi

            # The desktop entry and AppStream metadata, so the app shows up
            # in a desktop grid / software centre with its real name,
            # summary and keywords instead of just its binary name. Both are
            # plain .in files here (no itstool/intltool merge step upstream
            # runs at release time), so installing them is stripping the
            # .in suffix.
            if [ -f data/simple-scan.desktop.in ]; then
              mkdir -p $out/share/applications
              sed 's/\.in$//' data/simple-scan.desktop.in > $out/share/applications/org.gnome.SimpleScan.desktop
            fi
            if [ -f data/simple-scan.appdata.xml.in ]; then
              mkdir -p $out/share/metainfo
              sed 's/\.in$//' data/simple-scan.appdata.xml.in > $out/share/metainfo/org.gnome.SimpleScan.appdata.xml
            fi
            if [ -d data/icons ]; then
              mkdir -p $out/share/icons
              cp -r data/icons/. $out/share/icons/
            fi

            # -rbundler/setup puts the bundled gems on the load path, and
            # GI_TYPELIB_PATH keeps GObject-Introspection from re-registering
            # types the cairo gem's C extension has already registered.
            makeWrapper ${gems.wrappedRuby}/bin/ruby $out/bin/${launcher} \
              --add-flags "-rbundler/setup" \
              --add-flags "-I$out/share/simple-scan/lib" \
              --add-flags "$out/share/simple-scan/exe/${launcher}" \
              --set GI_TYPELIB_PATH "${typelibPath}" \
              --set SIMPLE_SCAN_SANE_LIB "${saneBackends}/lib/libsane.so.1" \
              --prefix XDG_DATA_DIRS : "$out/share" \
              --prefix XDG_DATA_DIRS : "$out/share/gsettings-schemas/simple-scan-0.1.0" \
              --prefix XDG_DATA_DIRS : "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}" \
              --prefix XDG_DATA_DIRS : "${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}" \
              --prefix XDG_DATA_DIRS : "${pkgs.adwaita-icon-theme}/share"

            runHook postInstall
          '';

          meta = {
            description = "A Ruby GTK4 / Libadwaita port of simple-scan";
            mainProgram = launcher;
            platforms = pkgs.lib.platforms.linux;
          };
        };

        apps.default = utils.lib.mkApp { drv = self.packages.${system}.default; };

        devShells.default = pkgs.mkShell {
          name = "simple-scan-devshell";

          packages = [
            gems
            gems.wrappedRuby
            pkgs.bundler
            pkgs.bundix
            pkgs.pkg-config
            pkgs.glib.dev
            pkgs.gettext
            # rxgettext, the extractor `rake pot` drives. GNU xgettext claims
            # to support Ruby but only shells out to this, so without it
            # `xgettext --language=Ruby` fails.
            pkgs.rubyPackages_3_4.gettext
            # The spec runner. The suite is plain RSpec, so this is enough.
            pkgs.rubyPackages_3_4.rspec
            # This machine may have no display server at all, so the shell
            # carries one it can start itself: `xvfb-run ruby exe/<app>` both
            # launches the app and is how test/drive_*.rb is run.
            pkgs.xvfb-run
            pkgs.gsettings-desktop-schemas
            pkgs.adwaita-icon-theme
            saneBackends
          ] ++ gtkStack;

          # Icons, GSettings schemas and the GTK portal all resolve through
          # XDG_DATA_DIRS; without these the window opens with blank icons.
          shellHook = ''
            export XDG_DATA_DIRS="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}:${pkgs.adwaita-icon-theme}/share:$XDG_DATA_DIRS"
            export GI_TYPELIB_PATH="${typelibPath}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
            export RUBYLIB="$PWD/lib''${RUBYLIB:+:$RUBYLIB}"
            # Compiled on every shell entry, not left for a developer to
            # remember a manual step — otherwise the schema is only reachable
            # after that step and Gio::Settings aborts the process instead.
            if [ -d data/schemas ]; then
              ${pkgs.glib.dev}/bin/glib-compile-schemas data/schemas
              export GSETTINGS_SCHEMA_DIR="$PWD/data/schemas"
            fi
            unset BUNDLE_GEMFILE BUNDLE_FROZEN
            # No real scanner is attached in this shell, so Scanner talks to
            # SANE's own "test" backend — lib/sane_api.rb's dlopen target and
            # the config dir that enables just that one backend.
            export SIMPLE_SCAN_SANE_LIB="${saneBackends}/lib/libsane.so.1"
            export SANE_CONFIG_DIR="${saneTestConfig}/etc/sane.d"
            echo "simple-scan devshell — ruby $(ruby -e 'print RUBY_VERSION')"
            echo "run the app:   xvfb-run ruby exe/simple-scan"
            echo "drive the app: xvfb-run ruby test/drive_*.rb"
            echo "run the specs: ruby -e 'require \"rspec/core\"; exit RSpec::Core::Runner.run([\"--format\", \"progress\", \"--require\", \"spec_helper\", \"spec\"])'"
          '';
        };
      });
}
