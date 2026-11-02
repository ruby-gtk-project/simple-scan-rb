# frozen_string_literal: true

require 'gtk4'

# Resources locates the files upstream's build installs beside the binary —
# the hicolor icons under data/icons, the compiled message catalogues under
# data/locale — and registers the icon directory with the GTK icon theme.
#
# Ported from data/meson.build and data/icons/meson.build. Upstream installs
# data/icons/scalable/actions/*.svg into $datadir/icons/hicolor and compiles
# po/ into $datadir/locale, both of which GTK and gettext then find on their
# default search paths because they sit inside a system prefix.
#
# This port is run from a git checkout as often as from an installed gem, so
# there is no prefix to rely on: the data directory is the one shipped in the
# gem (data/ beside lib/) and, when a packager has installed the files system
# wide instead, the first XDG data directory that carries them. Nothing here
# installs anything; it only reports where the files already are.
module Resources
  # data/ sits beside lib/ in both the checkout and the built gem, because
  # the gemspec packages data/**/* .
  BUNDLED_DIR = File.expand_path('../data', __dir__)

  # The subdirectory a packager's copy lands in under an XDG data directory.
  INSTALLED_LEAF = 'simple-scan-rb'

  DEFAULT_XDG_DATA_DIRS = '/usr/local/share:/usr/share'

  class << self
    # The directory holding icons/ and locale/, or nil when neither the
    # bundled copy nor an installed copy exists.
    def data_dir
      @data_dir ||= candidate_data_dirs.find { |dir| File.directory?(dir) }
    end

    # The hicolor icon theme directory shipped with the port, or nil when the
    # data directory is missing or carries no icons.
    def icon_dir
      @icon_dir ||= existing_subdirectory('icons')
    end

    # The directory compiled catalogues live in, as gettext expects it:
    # <locale_dir>/<lang>/LC_MESSAGES/<domain>.mo. Reported whether or not it
    # exists yet, because gettext treats a missing directory as "no
    # translations" and falls back to the untranslated message, which is the
    # right behaviour in a checkout where `rake i18n:mo` has not been run.
    def locale_dir
      @locale_dir ||= File.join(data_dir || BUNDLED_DIR, 'locale')
    end

    # Teaches the display's icon theme about data/icons, so the three action
    # icons upstream ships — crop-symbolic, scan-type-adf-symbolic and
    # scan-type-batch-symbolic — resolve the way the stock symbolic icons do.
    #
    # Gtk::IconTheme.get_for_display needs a display, so this is called from
    # the application's activate handler rather than at require time. Calling
    # it twice is harmless: a path already on the list is not added again.
    def install_icon_search_path(display = Gdk::Display.default)
      [display, icon_dir].all?.then do |usable|
        usable && Gtk::IconTheme.get_for_display(display).tap do |theme|
          theme.search_path.include?(icon_dir).then do |known|
            known || theme.add_search_path(icon_dir)
          end
        end
      end
    end

    private

      def existing_subdirectory(leaf)
        data_dir&.then { |dir| File.join(dir, leaf) }&.then do |path|
          File.directory?(path).then { |exists| exists && path }
        end
      end

      def candidate_data_dirs
        [
          BUNDLED_DIR,
          *xdg_data_dirs.map { |dir| File.join(dir, INSTALLED_LEAF) },
        ]
      end

      def xdg_data_dirs
        ENV.fetch('XDG_DATA_DIRS', DEFAULT_XDG_DATA_DIRS).split(':').reject(&:empty?)
      end
  end
end
