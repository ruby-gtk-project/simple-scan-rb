# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative 'page'
require_relative 'scan_options'
require_relative 'translations'

# ScanOptionsPopover is the popover beside the Scan button: what to scan
# (one page, the feeder, or page after page from the flatbed), whether the
# document is text or an image, and a way into Preferences.
#
# Ported from the GtkPopover with id scan_options_popover in upstream's
# data/ui/app-window.ui, with the toggled callbacks and set_scan_type /
# set_document_hint from src/app-window.vala.
#
# Upstream's GtkRadioButtons become GTK4 check buttons sharing a group, which
# is how GTK4 spells a radio group.
class ScanOptionsPopover < Gtk::Popover
  include Translations
  extend Translations

  include Signals

  # Each scan type's label, the icon the Scan button takes while it is
  # selected, and its tooltip, from the UI file.
  SCAN_TYPES = {
    ScanType::SINGLE => [_('_Single Page'), 'scanner-symbolic'],
    ScanType::ADF    => [_('All Pages From _Feeder'), 'scan-type-adf-symbolic'],
    ScanType::BATCH  => [_('_Multiple Pages From Flatbed'), 'scan-type-batch-symbolic'],
  }.freeze

  DOCUMENT_HINTS = {
    'text'  => [_('_Text'), 'x-office-document-symbolic'],
    'photo' => [_('_Image'), 'image-x-generic-symbolic'],
  }.freeze

  def initialize
    super()
    @updating = false
    @scan_type = ScanType::SINGLE
    @document_hint = 'photo'
  end

  def build
    tap do |popover|
      popover.child = content_box

      content_box.tap do |box|
        SCAN_TYPES.each_key { |type| box.append(scan_type_button(type)) }
        box.append(hint_separator)
        DOCUMENT_HINTS.each_key { |hint| box.append(document_hint_button(hint)) }
        box.append(preferences_separator)
        box.append(preferences_button)

        SCAN_TYPES.each_key do |type|
          scan_type_button(type).signal_connect('toggled') do |button|
            if button.active? && !@updating
              choose_scan_type(type)
            end
          end
        end

        DOCUMENT_HINTS.each_key do |hint|
          document_hint_button(hint).signal_connect('toggled') do |button|
            if button.active? && !@updating
              choose_document_hint(hint)
            end
          end
        end

        preferences_button.signal_connect('clicked') do
          popover.popdown
          emit(:preferences)
        end
      end
    end
  end

  # Memoized widget methods

  def content_box
    @content_box ||= Gtk::Box.new(:vertical, 6).tap do |box|
      box.margin_top = 6
      box.margin_bottom = 6
      box.margin_start = 6
      box.margin_end = 6
    end
  end

  def scan_type_button(type)
    scan_type_buttons[type] ||= radio_button(*SCAN_TYPES[type]).tap do |button|
      unless type == SCAN_TYPES.keys.first
        button.group = scan_type_button(SCAN_TYPES.keys.first)
      end
    end
  end

  def document_hint_button(hint)
    document_hint_buttons[hint] ||= radio_button(*DOCUMENT_HINTS[hint]).tap do |button|
      unless hint == DOCUMENT_HINTS.keys.first
        button.group = document_hint_button(DOCUMENT_HINTS.keys.first)
      end
    end
  end

  def hint_separator = @hint_separator ||= Gtk::Separator.new(:horizontal)

  def preferences_separator = @preferences_separator ||= Gtk::Separator.new(:horizontal)

  def preferences_button
    @preferences_button ||= Gtk::Button.new.tap do |button|
      button.label = _('_Preferences')
      button.use_underline = true
      button.add_css_class('flat')
    end
  end

  def scan_type = @scan_type

  def document_hint = @document_hint

  # The icon the Scan button wears for the current scan type.
  def scan_type_icon = SCAN_TYPES.fetch(@scan_type, SCAN_TYPES[ScanType::SINGLE]).last

  # The icon the document-hint button wears.
  def document_hint_icon = DOCUMENT_HINTS.fetch(@document_hint, DOCUMENT_HINTS['photo']).last

  # Upstream's set_scan_type: move the radio without that move reading back as
  # a user choice.
  def scan_type=(type)
    if SCAN_TYPES.key?(type)
      @scan_type = type
    else
      @scan_type = ScanType::SINGLE
    end
    @updating = true
    scan_type_button(@scan_type).active = true
    @updating = false
    emit(:scan_type_changed, @scan_type)
  end

  # Upstream's set_document_hint without its save flag; the window decides
  # whether a change is worth writing to settings.
  def document_hint=(hint)
    if DOCUMENT_HINTS.key?(hint)
      @document_hint = hint
    else
      @document_hint = 'photo'
    end
    @updating = true
    document_hint_button(@document_hint).active = true
    @updating = false
    emit(:document_hint_changed, @document_hint)
  end

  private

    def scan_type_buttons = @scan_type_buttons ||= {}

    def document_hint_buttons = @document_hint_buttons ||= {}

    def radio_button(label, icon_name)
      Gtk::CheckButton.new.tap do |button|
        button.child = Gtk::Box.new(:horizontal, 6).tap do |box|
          box.append(Gtk::Image.new.tap { |image| image.icon_name = icon_name })
          box.append(Gtk::Label.new(label).tap { |text| text.use_underline = true })
        end
      end
    end

    def choose_scan_type(type)
      @scan_type = type
      emit(:scan_type_changed, type)
    end

    def choose_document_hint(hint)
      @document_hint = hint
      emit(:document_hint_changed, hint)
    end
end
