# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'gtk4'

require_relative 'scan_options'

# Settings holds the keys of upstream's org.gnome.SimpleScan GSettings schema
# and the window state upstream keeps beside it in a key file.
#
# Ported from data/org.gnome.SimpleScan.gschema.xml, plus the load_state and
# save_state pair in src/app-window.vala.
#
# Upstream reads the first group through GSettings, which needs a schema
# compiled into the system's glib-2.0/schemas directory; requiring an install
# step before the app will start from a checkout is worse than the
# alternative, so the same keys, defaults, ranges and choices are backed by a
# JSON file under XDG_CONFIG_HOME. The state group keeps upstream's format and
# location exactly — the same key file at $XDG_CACHE_HOME/simple-scan/state —
# because nothing has to be installed for that to work.
class Settings
  DEFAULTS = {
    'selected-device' => '',
    'document-type'   => 'photo',
    'paper-width'     => 0,
    'paper-height'    => 0,
    'brightness'      => 0,
    'contrast'        => 0,
    'text-dpi'        => 150,
    'photo-dpi'       => 300,
    'page-side'       => 'both',
    'save-directory'  => '',
    'save-format'     => 'application/pdf',
    'jpeg-quality'    => 75,
    'page-delay'      => 1000,
  }.freeze

  # The <choices> and <range> elements of the schema, enforced on write the
  # way GSettings enforces them.
  CHOICES = {
    'document-type' => %w[text photo],
    'page-side'     => %w[front back both],
  }.freeze

  RANGES = {
    'jpeg-quality' => (0..100),
    'page-delay'   => (0..15_000),
  }.freeze

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

  def initialize(config_path: nil, state_path: nil)
    @config_path = config_path || default_config_path
    @state_path = state_path || default_state_path
    @values = DEFAULTS.merge(read_config)
    load_state
  end

  def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

  def []=(key, value)
    @values[key.to_s] = clamp(key.to_s, value)
    write_config
    @values[key.to_s]
  end

  def get_int(key) = self[key].to_i

  def get_string(key) = self[key].to_s

  def set_int(key, value)
    self[key] = value.to_i
  end

  def set_string(key, value)
    self[key] = value.to_s
  end

  # page-side is an enum key in the schema; these two are the get_enum and
  # set_enum upstream calls on it.
  def page_side = ScanSide.from_name(self['page-side'])

  def page_side=(side)
    self['page-side'] = ScanSide.to_name(side)
  end

  def config_location = @config_path

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

    def default_config_path
      File.join(config_dir, 'simple-scan', 'settings.json')
    end

    def default_state_path
      File.join(cache_dir, 'simple-scan', 'state')
    end

    def config_dir = ENV['XDG_CONFIG_HOME'].to_s.empty? ? File.join(Dir.home, '.config') : ENV['XDG_CONFIG_HOME']

    def cache_dir = ENV['XDG_CACHE_HOME'].to_s.empty? ? File.join(Dir.home, '.cache') : ENV['XDG_CACHE_HOME']

    def read_config
      JSON.parse(File.read(@config_path)).then { |parsed| parsed.is_a?(Hash) ? parsed : {} }
    rescue SystemCallError, JSON::ParserError
      {}
    end

    def write_config
      FileUtils.mkdir_p(File.dirname(@config_path))
      File.write(@config_path, "#{JSON.pretty_generate(@values)}\n")
    rescue SystemCallError => e
      warn "Failed to write settings: #{e.message}"
    end

    def clamp(key, value)
      if CHOICES.key?(key)
        CHOICES[key].include?(value.to_s) ? value.to_s : DEFAULTS[key]
      elsif RANGES.key?(key)
        [[value.to_i, RANGES[key].first].max, RANGES[key].last].min
      else
        value
      end
    end

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
