# frozen_string_literal: true

require 'adwaita'

require_relative 'simple/scan/rb/version'
require_relative 'translations'

# AboutDialog is the About window.
#
# Ported from show_about in upstream's src/app-window.vala, which calls
# Gtk.show_about_dialog with these strings. Here it is an Adwaita::AboutDialog,
# which is the Adwaita equivalent and takes a developer list rather than an
# authors list.
class AboutDialog < Adwaita::AboutDialog
  include Translations
  extend Translations

  DEVELOPERS = ['Robert Ancell <robert.ancell@canonical.com>'].freeze
  WEBSITE = 'https://gitlab.gnome.org/GNOME/simple-scan'

  def build
    tap do |dialog|
      # Title of the about dialog
      dialog.title = _('About Document Scanner')
      dialog.application_name = _('Document Scanner')
      dialog.application_icon = 'scanner-symbolic'
      dialog.version = Simple::Scan::Rb::VERSION
      # Description of the program
      dialog.comments = _('Simple document scanning tool')
      dialog.developers = DEVELOPERS
      dialog.translator_credits = _('translator-credits')
      dialog.website = WEBSITE
      dialog.copyright = 'Copyright © 2009-2018 Canonical Ltd.'
      # Adw.AboutDialog fills in the full GPL-3.0 text itself for a known
      # SPDX license_type; setting `license=` as well made it try to parse
      # that text as Pango markup, which failed on the bare
      # "<http://www.gnu.org/licenses/>" URL (Gtk-WARNING: Failed to set
      # text ... from markup).
      dialog.license_type = :gpl_3_0
    end
  end
end
