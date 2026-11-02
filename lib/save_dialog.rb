# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative 'alerts'
require_relative 'book'
require_relative 'settings'

# SaveDialog asks where to save the document, in what format, and at what
# compression.
#
# Ported from choose_file_location, check_overwrite, mime_type_to_extension,
# extension_to_mime_type and uri_to_mime_type in upstream's
# src/app-window.vala.
#
# Upstream puts the format combo and the compression slider into the save
# dialog itself, through Gtk.FileChooser's extra widget. GTK4 removed that —
# Gtk::FileDialog is a portal-backed dialog with no place to put a widget —
# so the format and compression are asked first, in a dialog of their own,
# and the file chooser that follows is pre-filled with a name carrying the
# matching extension. Picking a format still writes it to settings as soon as
# it is chosen, and the compression slider still writes jpeg-quality live,
# exactly as upstream's do.
class SaveDialog < Adwaita::Dialog
  # Label and mime type per format, in upstream's order.
  FORMATS = [
    # Save dialog: label for saving in PDF format
    ['PDF (multi-page document)', 'application/pdf'],
    # Save dialog: label for saving in JPEG format
    ['JPEG (compressed)', 'image/jpeg'],
    # Save dialog: label for saving in PNG format
    ['PNG (lossless)', 'image/png'],
  ].freeze

  EXTENSIONS = {
    'application/pdf' => 'pdf',
    'image/jpeg'      => 'jpg',
    'image/png'       => 'png',
  }.freeze

  # Default filename to use when saving a document; the extension is added to it
  DEFAULT_BASENAME = 'Scanned Document'

  def self.mime_type_to_extension(mime_type) = EXTENSIONS[mime_type]

  def self.extension_to_mime_type(extension) = EXTENSIONS.key(extension.to_s.downcase)

  # Upstream's uri_to_mime_type, which falls back to JPEG for a name with no
  # extension or an extension it does not know.
  def self.path_to_mime_type(path)
    File.extname(path.to_s).delete_prefix('.').then do |extension|
      extension_to_mime_type(extension) || 'image/jpeg'
    end
  end

  def initialize(settings, book, current_path: nil, &on_chosen)
    super()
    @settings = settings
    @book = book
    @current_path = current_path
    @on_chosen = on_chosen
    # Save dialog: dialog title
    self.title = 'Save As…'
    self.content_width = 520
  end

  def build
    tap do |dialog|
      dialog.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = content_box

        header_bar.pack_end(save_button)

        save_button.signal_connect('clicked') { choose_location }

        content_box.tap do |box|
          box.append(options_group)

          options_group.tap do |group|
            group.add(format_row)
            group.add(quality_row)

            format_row.signal_connect('notify::selected') { format_changed }
            quality_scale.adjustment.signal_connect('value-changed') { quality_changed }
          end
        end
      end

      load_settings
    end
  end

  # Memoized widget methods

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def save_button
    @save_button ||= Gtk::Button.new.tap do |button|
      button.label = '_Save'
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

  def options_group = @options_group ||= Adwaita::PreferencesGroup.new

  def format_row
    @format_row ||= Adwaita::ComboRow.new.tap do |row|
      # Label in save dialog beside combo box to choose the file format
      row.title = 'File format'
      row.model = Gtk::StringList.new(FORMATS.map(&:first))
    end
  end

  def quality_row
    @quality_row ||= Adwaita::ActionRow.new.tap do |row|
      # Label in save dialog beside the compression slider
      row.title = 'Compression'
      row.add_suffix(quality_scale)
    end
  end

  def quality_scale
    @quality_scale ||= Gtk::Scale.new(
      :horizontal,
      Gtk::Adjustment.new(
        75,
        0,
        100,
        1,
        10,
        0,
      ),
    ).tap do |scale|
      scale.width_request = 250
      scale.draw_value = false
      scale.valign = :center
      # Label at the low end of the compression slider
      scale.add_mark(0, :bottom, '<small>Minimum size</small>')
      scale.add_mark(75, :bottom, nil)
      scale.add_mark(90, :bottom, nil)
      # Label at the high end of the compression slider
      scale.add_mark(100, :bottom, '<small>Full detail</small>')
    end
  end

  def file_dialog
    @file_dialog ||= Gtk::FileDialog.new.tap do |dialog|
      # Save dialog: dialog title
      dialog.title = 'Save As…'
      dialog.filters = filters
      dialog.default_filter = image_filter
    end
  end

  def filters
    @filters ||= Gio::ListStore.new(Gtk::FileFilter).tap do |store|
      store.append(image_filter)
      store.append(all_filter)
    end
  end

  def image_filter
    @image_filter ||= Gtk::FileFilter.new.tap do |filter|
      # Save dialog: filter name to show only supported image files
      filter.name = 'Image Files'
      EXTENSIONS.each_key { |mime_type| filter.add_mime_type(mime_type) }
    end
  end

  def all_filter
    @all_filter ||= Gtk::FileFilter.new.tap do |filter|
      # Save dialog: filter name to show all files
      filter.name = 'All Files'
      filter.add_pattern('*')
    end
  end

  def mime_type = FORMATS.dig(selected_format_index, 1) || 'application/pdf'

  def quality = quality_scale.adjustment.value.to_i

  private

    def selected_format_index
      format_row.selected.then { |index| index == Gtk::INVALID_LIST_POSITION ? 0 : index }
    end

    def load_settings
      @settings.get_string('save-format').then do |stored|
        format_row.selected = FORMATS.index { |(_label, mime)| mime == stored } || 0
      end
      quality_scale.adjustment.value = @settings.get_int('jpeg-quality')
      update_quality_visibility
    end

    def format_changed
      @settings.set_string('save-format', mime_type)
      update_quality_visibility
    end

    def quality_changed
      @settings.set_int('jpeg-quality', quality)
    end

    # Upstream hides the compression slider for PNG, which has no quality
    # setting.
    def update_quality_visibility
      quality_row.visible = mime_type != 'image/png'
    end

    def choose_location
      file_dialog.tap do |dialog|
        dialog.initial_name = initial_name
        initial_folder.then do |folder|
          unless folder.nil?
            dialog.initial_folder = folder
          end
        end

        dialog.save(root, nil) { |_source, result| location_chosen(dialog, result) }
      end
    end

    def initial_name
      if @current_path.nil?
        "#{DEFAULT_BASENAME}.#{self.class.mime_type_to_extension(mime_type)}"
      else
        File.basename(@current_path)
      end
    end

    # Upstream defaults to the remembered save directory and falls back to the
    # user's Documents directory.
    def initial_folder
      directory.then { |path| path.nil? ? nil : Gio::File.new_for_path(path) }
    end

    def directory
      @settings.get_string('save-directory').then do |stored|
        if stored.empty?
          GLib.get_user_special_dir(:documents) || Dir.home
        else
          stored
        end
      end
    end

    def location_chosen(dialog, result)
      dialog.save_finish(result).then do |file|
        unless file.nil?
          accept(with_extension(file.path))
        end
      end
    rescue GLib::Error
      nil
    end

    # Upstream adds the format's extension when the chosen name has none.
    def with_extension(path)
      if File.extname(path).empty?
        "#{path}.#{self.class.mime_type_to_extension(mime_type)}"
      else
        path
      end
    end

    def accept(path)
      confirm_overwrite(extra_existing_files(path)) do
        @settings.set_string('save-directory', File.dirname(path))
        @on_chosen&.call(path, self.class.path_to_mime_type(path), quality)
        close
      end
    end

    # The file chooser asks about the name it was given, but a multi-page PNG
    # or JPEG save writes one file per page beside it. Upstream's
    # check_overwrite asks about every file it is about to write, so the
    # siblings are asked about here.
    def extra_existing_files(path)
      indexed_files(path).select { |candidate| candidate != path && File.exist?(candidate) }
    end

    def indexed_files(path)
      if self.class.path_to_mime_type(path) == 'application/pdf'
        [path]
      else
        @book.n_pages.times.map { |index| make_indexed_file(path, index, @book.n_pages) }
      end
    end

    # Asks about each file in turn, and only runs the block if every answer
    # was Replace.
    def confirm_overwrite(files, &on_confirmed)
      if files.empty?
        on_confirmed.call
      else
        Alerts.confirm_overwrite(self, File.basename(files.first)) do |replace|
          if replace
            confirm_overwrite(files.drop(1), &on_confirmed)
          end
        end
      end
    end
end
