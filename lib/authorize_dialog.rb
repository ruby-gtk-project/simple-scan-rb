# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative 'translations'

# AuthorizeDialog asks for the username and password a network scanner wants.
#
# Ported from upstream's src/authorize-dialog.vala and
# data/ui/authorize-dialog.ui. Upstream is a Gtk.Dialog it runs modally,
# reading the two entries afterwards; GTK4 has no run, so the credentials go
# to the block handed to build instead.
class AuthorizeDialog < Adwaita::Dialog
  include Translations
  extend Translations

  def initialize(description, &on_authorized)
    super()
    @description = description
    @on_authorized = on_authorized
    # Title of the authorization dialog
    self.title = _('Authorize')
    self.content_width = 420
  end

  def build
    tap do |dialog|
      dialog.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = content_box

        header_bar.pack_end(authorize_button)

        authorize_button.signal_connect('clicked') { authorize }

        content_box.tap do |box|
          box.append(description_label)
          box.append(credentials_group)

          credentials_group.tap do |group|
            group.add(username_row)
            group.add(password_row)

            password_row.signal_connect('entry-activated') { authorize }
          end
        end
      end
    end
  end

  def username = username_row.text

  def password = password_row.text

  # Memoized widget methods

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def authorize_button
    @authorize_button ||= Gtk::Button.new.tap do |button|
      # Button to submit the authorization dialog
      button.label = _('_Authorize')
      button.use_underline = true
      button.add_css_class('suggested-action')
    end
  end

  def content_box
    @content_box ||= Gtk::Box.new(:vertical, 12).tap do |box|
      box.margin_top = 12
      box.margin_bottom = 12
      box.margin_start = 12
      box.margin_end = 12
    end
  end

  def description_label
    @description_label ||= Gtk::Label.new(@description).tap do |label|
      label.wrap = true
      label.xalign = 0
      label.max_width_chars = 44
    end
  end

  def credentials_group = @credentials_group ||= Adwaita::PreferencesGroup.new

  def username_row
    @username_row ||= Adwaita::EntryRow.new.tap do |row|
      # Label beside username entry
      row.title = _('Username for resource')
    end
  end

  def password_row
    @password_row ||= Adwaita::PasswordEntryRow.new.tap do |row|
      # Label beside password entry
      row.title = _('Password')
    end
  end

  private

    def authorize
      @on_authorized&.call(username, password)
      close
    end
end
