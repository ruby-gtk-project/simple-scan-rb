# frozen_string_literal: true

require 'fileutils'
require 'gtk4'

require_relative 'scan_options'

# Settings holds the keys of upstream's org.gnome.SimpleScan GSettings schema
# and the window state upstream keeps beside it in a key file.
#
# Ported from data/org.gnome.SimpleScan.gschema.xml (now data/schemas/
# org.gnome.SimpleScan.gschema.xml in this port, compiled by flake.nix), plus
# the load_state and save_state pair in src/app-window.vala.
#
# Upstream reads the first group through Gio::Settings (GSettings), which
# needs the schema compiled into a glib-2.0/schemas directory the process can
# see via GSETTINGS_SCHEMA_DIR or XDG_DATA_DIRS — flake.nix's devShell and
# packages.default both set this up, so this class talks to Gio::Settings
# directly rather than re-implementing the schema's defaults, choices and
# ranges in Ruby. The state group keeps upstream's format and location
# exactly — the same key file at $XDG_CACHE_HOME/simple-scan/state — because
# that part of upstream was never a GSettings key in the first place.
class Settings
  SCHEMA_ID = 'org.gnome.SimpleScan'

  # The defaults load_state falls back to, from app-window.vala.
  STATE_DEFAULTS = {
    width:      600,
    height:     400,
    maximized:  false,
    fullscreen: false,
    scan_type:  ScanType::SINGLE,
  }.freeze

  attr_reader :window_width, :window_height, :scan_type
  attr_writer :window_width, :window_height, :scan_type

  def initialize(gsettings: nil, state_path: nil)
    @gsettings = gsettings || Gio::Settings.new(SCHEMA_ID)
    @state_path = state_path || default_state_path
    load_state
  end

  def [](key) = @gsettings.get_value(key.to_s)

  def []=(key, value)
    @gsettings.set_value(key.to_s, value)
    value
  end

  def get_int(key) = @gsettings.get_int(key.to_s)

  def get_string(key) = @gsettings.get_string(key.to_s)

  def set_int(key, value) = @gsettings.set_int(key.to_s, value.to_i)

  def set_string(key, value) = @gsettings.set_string(key.to_s, value.to_s)

  # page-side is an enum key in the schema (org.gnome.SimpleScan.PageSide);
  # these two are the get_enum and set_enum upstream calls on it. The enum's
  # nicks (front/back/both) are ScanSide's own names, so no translation table
  # is needed beyond ScanSide itself.
  def page_side = ScanSide.from_name(@gsettings.get_string('page-side'))

  def page_side=(side)
    @gsettings.set_string('page-side', ScanSide.to_name(side))
  end

  def config_location = SCHEMA_ID

  def state_location = @state_path

  def window_maximized? = @window_maximized

  def window_fullscreen? = @window_fullscreen

  def window_maximized=(value)
    if value
      @window_maximized = true
    else
      @window_maximized = false
    end
  end

  def window_fullscreen=(value)
    if value
      @window_fullscreen = true
    else
      @window_fullscreen = false
    end
  end

  # Upstream's load_state, including its refusal of a non-positive size.
  def load_state
    state_key_file.then do |file|
      @window_width = positive_or(
        state_integer(
          file,
          'window',
          'width',
          STATE_DEFAULTS[:width],
        ),
        STATE_DEFAULTS[:width],
      )
      @window_height =
        positive_or(
          state_integer(
            file,
            'window',
            'height',
            STATE_DEFAULTS[:height],
          ),
          STATE_DEFAULTS[:height],
        )
      @window_maximized = state_boolean(file, 'window', 'is-maximized')
      @window_fullscreen = state_boolean(file, 'window', 'is-fullscreen')
      @scan_type = ScanType.from_name(
        state_string(
          file,
          'scanner',
          'scan-type',
          ScanType.to_name(STATE_DEFAULTS[:scan_type]),
        ),
      )
    end
  end

  # Upstream's save_state, coalesced behind a 100ms timeout so a resize does
  # not write the file on every allocation. force writes immediately.
  def save_state(force: false)
    if force
      write_state
    else
      schedule_state_write
    end
  end

  # True when a coalesced write is still pending, which is what upstream's
  # save_state_timeout != 0 check asks before it forces one on quit.
  def state_write_pending? = !@state_timeout.nil?

  private

    def default_state_path
      File.join(cache_dir, 'simple-scan', 'state')
    end

    def cache_dir = ENV['XDG_CACHE_HOME'].to_s.empty? ? File.join(Dir.home, '.cache') : ENV['XDG_CACHE_HOME']

    def positive_or(value, fallback) = value.positive? ? value : fallback

    # GLib::KeyFile#load_from_file raises GLib::FileError, which is not a
    # GLib::Error, so both are caught. A missing file is the ordinary first
    # run and is not worth a warning, which is upstream's FileError.NOENT
    # check.
    def state_key_file
      GLib::KeyFile.new.tap { |file| file.load_from_file(@state_path, :none) }
    rescue StandardError => e
      if File.exist?(@state_path)
        warn "Failed to load state: #{e.message}"
      end
      GLib::KeyFile.new
    end

    def state_string(file, group, key, fallback)
      file.get_string(group, key)
    rescue StandardError
      fallback
    end

    def state_integer(file, group, key, fallback = 0)
      file.get_integer(group, key)
    rescue StandardError
      fallback
    end

    def state_boolean(file, group, key, fallback = false)
      file.get_boolean(group, key)
    rescue StandardError
      fallback
    end

    def schedule_state_write
      unless @state_timeout.nil?
        GLib::Source.remove(@state_timeout)
      end
      @state_timeout = GLib::Timeout.add(100) do
        @state_timeout = nil
        write_state
        false
      end
    end

    def write_state
      GLib::KeyFile.new.tap do |file|
        file.set_integer('window', 'width', @window_width)
        file.set_integer('window', 'height', @window_height)
        file.set_boolean('window', 'is-maximized', @window_maximized)
        file.set_boolean('window', 'is-fullscreen', @window_fullscreen)
        file.set_string('scanner', 'scan-type', ScanType.to_name(@scan_type))
      end.then { |file| store_state(file) }
    end

    def store_state(file)
      FileUtils.mkdir_p(File.dirname(@state_path))
      File.write(@state_path, file.to_data)
    rescue SystemCallError => e
      warn "Failed to write state: #{e.message}"
    end
end
