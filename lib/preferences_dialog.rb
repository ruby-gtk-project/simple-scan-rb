# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative 'scan_options'
require_relative 'settings'

# PreferencesDialog holds the scanning preferences: resolution for text and
# for image scans, which side of a page to scan, the paper size, brightness,
# contrast, and the delay between pages.
#
# Ported from upstream's src/preferences-dialog.vala and
# data/ui/preferences-dialog.ui. Every control writes straight through to
# settings as upstream's do, so there is no apply step.
#
# Upstream's HdyPreferencesWindow becomes an Adwaita::PreferencesDialog, and
# its GtkComboBox/GtkListStore pairs become Adwaita::ComboRow over a
# Gtk::StringList, which is how GTK4 spells the same thing. The page-delay
# radio group is a combo row too, because five radio buttons for one value is
# not how Adwaita lays out a preferences page.
class PreferencesDialog < Adwaita::PreferencesDialog
  DEFAULT_TEXT_DPI = 150
  DEFAULT_PHOTO_DPI = 300

  SCAN_RESOLUTIONS = [75, 150, 200, 300, 600, 1200, 2400].freeze

  # Width and height in tenths of a mm, and the label, from upstream's
  # paper_size_model.
  PAPER_SIZES = [
    # Combo box value for automatic paper size
    [0, 0, 'Automatic'],
    [1050, 1480, 'A6'],
    [1480, 2100, 'A5'],
    [2100, 2970, 'A4'],
    [2970, 4200, 'A3'],
    [2159, 2794, 'Letter'],
    [2159, 3556, 'Legal'],
    [1016, 1524, '4×6'],
  ].freeze

  PAGE_SIDES = [
    [ScanSide::FRONT, 'Front'],
    [ScanSide::BACK, 'Back'],
    [ScanSide::BOTH, 'Both'],
  ].freeze

  # Milliseconds, and the label, from the five radio buttons in the UI file.
  PAGE_DELAYS = [
    [0, 'No delay'],
    [3000, '3 second delay'],
    [6000, '6 second delay'],
    [10000, '10 second delay'],
    [15000, '15 second delay'],
  ].freeze

  def initialize(settings)
    super()
    @settings = settings
    @updating = false
    # Title of the preferences dialog
    self.title = 'Preferences'
  end

  def build
    tap do |dialog|
      dialog.add(scanning_page)

      scanning_page.tap do |page|
        page.add(scanning_group)
        page.add(quality_group)

        scanning_group.tap do |group|
          group.add(text_dpi_row)
          group.add(photo_dpi_row)
          group.add(page_side_row)
          group.add(paper_size_row)
          group.add(page_delay_row)
        end

        quality_group.tap do |group|
          group.add(brightness_row)
          group.add(contrast_row)
        end
      end

      load_settings
      connect_rows
    end
  end

  # Memoized widget methods

  def scanning_page
    @scanning_page ||= Adwaita::PreferencesPage.new.tap do |page|
      page.title = 'Scanning'
      page.icon_name = 'scanner-symbolic'
    end
  end

  def scanning_group
    @scanning_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      # Preferences dialog: section label for scanning settings
      group.title = 'Scanning'
    end
  end

  def quality_group
    @quality_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      # Preferences dialog: section label for image quality settings
      group.title = 'Quality'
    end
  end

  def text_dpi_row
    @text_dpi_row ||= combo_row('Text Resolution', dpi_labels(DEFAULT_TEXT_DPI))
  end

  def photo_dpi_row
    @photo_dpi_row ||= combo_row('Image Resolution', dpi_labels(DEFAULT_PHOTO_DPI))
  end

  def page_side_row
    @page_side_row ||= combo_row('Page Side', PAGE_SIDES.map(&:last))
  end

  def paper_size_row
    @paper_size_row ||= combo_row('Paper Size', PAPER_SIZES.map(&:last))
  end

  def page_delay_row
    @page_delay_row ||= combo_row('Delay Between Pages', PAGE_DELAYS.map(&:last))
  end

  def brightness_row
    @brightness_row ||= Adwaita::ActionRow.new.tap do |row|
      # Preferences dialog: label for the brightness scale
      row.title = 'Brightness'
      row.add_suffix(brightness_scale)
    end
  end

  def contrast_row
    @contrast_row ||= Adwaita::ActionRow.new.tap do |row|
      # Preferences dialog: label for the contrast scale
      row.title = 'Contrast'
      row.add_suffix(contrast_scale)
    end
  end

  def brightness_scale = @brightness_scale ||= marked_scale('Darker', 'Lighter')

  def contrast_scale = @contrast_scale ||= marked_scale('Less', 'More')

  # Accessors the window reads when it builds a ScanOptions

  def text_dpi = SCAN_RESOLUTIONS[selected_index(text_dpi_row)] || DEFAULT_TEXT_DPI

  def photo_dpi = SCAN_RESOLUTIONS[selected_index(photo_dpi_row)] || DEFAULT_PHOTO_DPI

  def page_side = PAGE_SIDES.dig(selected_index(page_side_row), 0) || ScanSide::BOTH

  # Width and height in tenths of a mm, which is the unit upstream's
  # paper-width and paper-height settings are in.
  def paper_size = PAPER_SIZES[selected_index(paper_size_row)].then { |size| size.nil? ? [0, 0] : size.first(2) }

  def page_delay = PAGE_DELAYS.dig(selected_index(page_delay_row), 0) || 0

  def brightness = brightness_scale.adjustment.value.to_i

  def contrast = contrast_scale.adjustment.value.to_i

  def brightness=(value)
    brightness_scale.adjustment.value = value
  end

  def contrast=(value)
    contrast_scale.adjustment.value = value
  end

  def page_delay=(milliseconds)
    select_page_delay(milliseconds)
  end

  private

    def dpi_labels(default_dpi)
      SCAN_RESOLUTIONS.map { |dpi| dpi_label(dpi, default_dpi) }
    end

    def dpi_label(dpi, default_dpi)
      if dpi == default_dpi
        # Preferences dialog: label for the default resolution in the resolution list
        format('%d dpi (default)', dpi)
      elsif dpi == 75
        # Preferences dialog: label for the minimum resolution in the resolution list
        format('%d dpi (draft)', dpi)
      elsif dpi == 1200
        # Preferences dialog: label for the maximum resolution in the resolution list
        format('%d dpi (high resolution)', dpi)
      else
        # Preferences dialog: label for a resolution value (dpi = dots per inch)
        format('%d dpi', dpi)
      end
    end

    def combo_row(title, labels)
      Adwaita::ComboRow.new.tap do |row|
        row.title = title
        row.model = Gtk::StringList.new(labels)
      end
    end

    # A scale marked at both ends and in the middle, which is how upstream
    # marks its brightness and contrast scales.
    def marked_scale(lower_label, upper_label)
      Gtk::Scale.new(
        :horizontal,
        Gtk::Adjustment.new(
          0,
          -100,
          100,
          1,
          10,
          0,
        ),
      ).tap do |scale|
        scale.width_request = 250
        scale.draw_value = false
        scale.valign = :center
        scale.add_mark(-100, :bottom, "<small>#{lower_label}</small>")
        scale.add_mark(0, :bottom, nil)
        scale.add_mark(100, :bottom, "<small>#{upper_label}</small>")
      end
    end

    def selected_index(row)
      row.selected.then { |index| index == Gtk::INVALID_LIST_POSITION ? 0 : index }
    end

    # Upstream reads every value out of settings in its constructor.
    def load_settings
      @updating = true
      select_dpi(text_dpi_row, @settings.get_int('text-dpi'), DEFAULT_TEXT_DPI)
      select_dpi(photo_dpi_row, @settings.get_int('photo-dpi'), DEFAULT_PHOTO_DPI)
      page_side_row.selected = PAGE_SIDES.index { |(side, _label)| side == @settings.page_side } || 2
      select_paper_size(@settings.get_int('paper-width'), @settings.get_int('paper-height'))
      select_page_delay(@settings.get_int('page-delay'))
      brightness_scale.adjustment.value = @settings.get_int('brightness')
      contrast_scale.adjustment.value = @settings.get_int('contrast')
      @updating = false
    end

    def connect_rows
      text_dpi_row.signal_connect('notify::selected') { store { @settings.set_int('text-dpi', text_dpi) } }
      photo_dpi_row.signal_connect('notify::selected') { store { @settings.set_int('photo-dpi', photo_dpi) } }
      page_side_row.signal_connect('notify::selected') { store { @settings.page_side = page_side } }
      paper_size_row.signal_connect('notify::selected') { store { store_paper_size } }
      page_delay_row.signal_connect('notify::selected') { store { @settings.set_int('page-delay', page_delay) } }
      brightness_scale.adjustment.signal_connect('value-changed') do
        store { @settings.set_int('brightness', brightness) }
      end
      contrast_scale.adjustment.signal_connect('value-changed') do
        store { @settings.set_int('contrast', contrast) }
      end
    end

    def store
      unless @updating
        yield
      end
    end

    def store_paper_size
      paper_size.then do |(width, height)|
        @settings.set_int('paper-width', width)
        @settings.set_int('paper-height', height)
      end
    end

    # Upstream falls back to the default resolution for a non-positive stored
    # value, and selects the nearest listed resolution.
    def select_dpi(row, stored_dpi, default_dpi)
      (stored_dpi.positive? ? stored_dpi : default_dpi).then do |dpi|
        row.selected = SCAN_RESOLUTIONS.index(dpi) || SCAN_RESOLUTIONS.index(default_dpi)
      end
    end

    # Upstream's set_paper_size, which falls back to Automatic for a size that
    # is not in the list.
    def select_paper_size(width, height)
      paper_size_row.selected =
        PAPER_SIZES.index { |(w, h, _label)| w == width && h == height } || 0
    end

    # Upstream's set_page_delay, which rounds a stored delay down to the
    # nearest offered one.
    def select_page_delay(milliseconds)
      page_delay_row.selected =
        PAGE_DELAYS.rindex { |(delay, _label)| milliseconds >= delay } || 0
    end
end
