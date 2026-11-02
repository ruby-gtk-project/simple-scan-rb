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

  # The license this software is under (GPL3+)
  LICENSE = <<~LICENSE
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
  LICENSE

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
      dialog.license_type = :gpl_3_0
      dialog.license = LICENSE
    end
  end
end
