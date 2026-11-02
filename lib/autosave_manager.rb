# frozen_string_literal: true

require 'fileutils'
require 'gtk4'

require_relative 'book'
require_relative 'page'

# AutosaveManager keeps a copy of the book on disk, so a crash or a power cut
# does not lose an unsaved scan.
#
# A direct port of upstream's src/autosave-manager.vala: the same key file at
# $XDG_CACHE_HOME/simple-scan/autosaves/autosave.book, the same keys in it,
# and the raw pixels of each page beside it in its own file.
class AutosaveManager
  AUTOSAVE_FILENAME = 'autosave.book'

  def initialize(directory: nil)
    @directory = directory || File.join(cache_dir, 'simple-scan', 'autosaves')
    @page_filenames = {}
    @book_handlers = {}
    @page_handlers = {}
    @update_timeout = nil
    @book = nil
  end

  attr_reader :book

  def path = File.join(@directory, AUTOSAVE_FILENAME)

  def exists? = File.exist?(path)

  # Watching a new book stops watching the old one, exactly as upstream's book
  # property setter does.
  def book=(value)
    @book.then do |previous|
      unless previous.nil?
        previous.pages.each { |page| on_page_removed(page) }
        @book_handlers.each { |name, handler| previous.off(name, handler) }
      end
    end

    @book = value
    @book_handlers = {
      page_added:   @book.on(:page_added) { |page| on_page_added(page) },
      page_removed: @book.on(:page_removed) { |page| on_page_removed(page) },
      reordered:    @book.on(:reordered) { on_changed },
      cleared:      @book.on(:cleared) { on_cleared },
    }
    @book.pages.each { |page| on_page_added(page) }
  end

  # Replaces the book's contents with the autosaved pages.
  def load
    @book.clear
    @page_filenames.clear

    read_key_file.then do |file|
      unless file.nil?
        value(file, 'simple-scan', 'pages').split(' ').each { |page_name| load_page(file, page_name) }
      end
    end
  end

  # Upstream's cleanup: drop the pending timeout and empty the directory.
  def cleanup
    unless @update_timeout.nil?
      GLib::Source.remove(@update_timeout)
    end
    @update_timeout = nil

    Dir.children(@directory).each { |name| File.unlink(File.join(@directory, name)) }
  rescue SystemCallError => e
    warn "Failed to delete autosaves: #{e.message}"
  end

  def on_page_added(page)
    @page_handlers[page] = {
      scan_finished: page.on(:scan_finished) { on_scan_finished(page) },
      crop_changed:  page.on(:crop_changed) { on_changed },
    }
  end

  def on_page_removed(page)
    @page_handlers.fetch(page, {}).each { |name, handler| page.off(name, handler) }
    @page_handlers.delete(page)

    @page_filenames[page].then do |filename|
      unless filename.nil?
        delete_pixels(filename)
      end
    end
    @page_filenames.delete(page)
  end

  def on_scan_finished(page)
    save_pixels(page)
    save(timeout: false)
  end

  def on_changed
    save
  end

  def on_cleared
    @page_filenames.clear
    save
  end

  private

    def cache_dir = ENV['XDG_CACHE_HOME'].to_s.empty? ? File.join(Dir.home, '.cache') : ENV['XDG_CACHE_HOME']

    def save(timeout: true)
      unless @update_timeout.nil?
        GLib::Source.remove(@update_timeout)
      end
      @update_timeout = nil

      if timeout
        @update_timeout = GLib::Timeout.add(100) do
          @update_timeout = nil
          real_save
          false
        end
      else
        real_save
      end
    end

    # GLib::KeyFile#load_from_file raises GLib::FileError rather than
    # GLib::Error, so both are caught here.
    def read_key_file
      GLib::KeyFile.new.tap { |file| file.load_from_file(path, :none) }
    rescue StandardError => e
      if File.exist?(path)
        warn "Could not load autosave information; not restoring any autosaves: #{e.message}"
      end
      nil
    end

    def load_page(file, page_name)
      pixels_filename = value(file, page_name, 'pixels-filename')
      read_pixels(pixels_filename).then do |pixels|
        if pixels_filename.empty? || !pixels.nil?
          append_page(
            file,
            page_name,
            pixels_filename,
            pixels,
          )
        end
      end
    end

    def append_page(file, page_name, pixels_filename, pixels)
      Page.from_data(
        scan_width:     integer(file, page_name, 'scan-width'),
        scan_height:    integer(file, page_name, 'scan-height'),
        rowstride:      integer(file, page_name, 'rowstride'),
        n_channels:     integer(file, page_name, 'n-channels'),
        depth:          integer(file, page_name, 'depth'),
        dpi:            integer(file, page_name, 'dpi'),
        scan_direction: ScanDirection.from_name(value(file, page_name, 'scan-direction')),
        color_profile:  presence(value(file, page_name, 'color-profile')),
        pixels:         pixels,
        has_crop:       boolean(file, page_name, 'has-crop'),
        crop_name:      presence(value(file, page_name, 'crop-name')),
        crop_x:         integer(file, page_name, 'crop-x'),
        crop_y:         integer(file, page_name, 'crop-y'),
        crop_width:     integer(file, page_name, 'crop-width'),
        crop_height:    integer(file, page_name, 'crop-height'),
      ).tap do |page|
        @page_filenames[page] = pixels_filename
        @book.append_page(page)
      end
    end

    def presence(text) = text.to_s.empty? ? nil : text

    def read_pixels(filename)
      if filename.to_s.empty?
        nil
      else
        File.binread(File.join(@directory, filename))
      end
    rescue SystemCallError
      warn 'Failed to load pixel information'
      nil
    end

    def value(file, group, key, fallback = '')
      file.get_value(group, key)
    rescue StandardError
      fallback
    end

    def integer(file, group, key, fallback = 0)
      file.get_integer(group, key)
    rescue StandardError
      fallback
    end

    def boolean(file, group, key, fallback = false)
      file.get_boolean(group, key)
    rescue StandardError
      fallback
    end

    # Upstream's real_save: one group per page that has data, and a "pages"
    # key listing the group names in order.
    def real_save
      GLib::KeyFile.new.tap do |file|
        pages_with_data.each_with_index.map { |page, index| save_page(file, page, index) }
          .then { |names| file.set_value('simple-scan', 'pages', names.join(' ')) }
      end.then { |file| store(file) }
    end

    def pages_with_data = @book.pages.select(&:has_data?)

    def save_page(file, page, index)
      "page-#{index}".tap do |page_name|
        file.set_integer(page_name, 'scan-width', page.scan_width)
        file.set_integer(page_name, 'scan-height', page.scan_height)
        file.set_integer(page_name, 'rowstride', page.rowstride)
        file.set_integer(page_name, 'n-channels', page.n_channels)
        file.set_integer(page_name, 'depth', page.depth)
        file.set_integer(page_name, 'dpi', page.dpi)
        file.set_value(page_name, 'scan-direction', ScanDirection.to_name(page.scan_direction))
        file.set_value(page_name, 'color-profile', page.color_profile.to_s)
        file.set_value(page_name, 'pixels-filename', @page_filenames.fetch(page, '').to_s)
        file.set_boolean(page_name, 'has-crop', page.has_crop?)
        file.set_value(page_name, 'crop-name', page.crop_name.to_s)
        file.set_integer(page_name, 'crop-x', page.crop_x)
        file.set_integer(page_name, 'crop-y', page.crop_y)
        file.set_integer(page_name, 'crop-width', page.crop_width)
        file.set_integer(page_name, 'crop-height', page.crop_height)
      end
    end

    def store(file)
      FileUtils.mkdir_p(@directory)
      File.write(path, file.to_data)
    rescue SystemCallError => e
      warn "Failed to write autosave: #{e.message}"
    end

    def save_pixels(page)
      "#{page.object_id}.pixels".tap do |filename|
        @page_filenames[page] = filename
        write_pixels(File.join(@directory, filename), page.pixels)
      end
    end

    def write_pixels(target, pixels)
      FileUtils.mkdir_p(@directory)
      File.binwrite(target, pixels)
    rescue SystemCallError => e
      warn "Failed to autosave page contents: #{e.message}"
    end

    def delete_pixels(filename)
      File.unlink(File.join(@directory, filename))
    rescue SystemCallError
      nil
    end
end
