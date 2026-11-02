# frozen_string_literal: true

# Scan option value types.
#
# Ported from the value classes and enumerations declared at the top of
# upstream's src/scanner.vala — ScanDevice, ScanPageInfo, ScanLine and
# ScanOptions, together with the ScanMode, ScanType and ScanSide enumerations
# and the type_to_string/type_from_string pair Scanner exposes as statics.
# The SANE-driving service itself is not part of this file.

# ScanMode mirrors upstream's ScanMode enumeration.
module ScanMode
  DEFAULT = :default
  COLOR = :color
  GRAY = :gray
  LINEART = :lineart
  ALL = [DEFAULT, COLOR, GRAY, LINEART].freeze
end

# ScanType mirrors upstream's ScanType enumeration. The symbol names are the
# strings Scanner.type_to_string produces, which is also what the window's
# saved state file holds.
module ScanType
  SINGLE = :single
  ADF = :adf
  BATCH = :batch
  ALL = [SINGLE, ADF, BATCH].freeze

  # Upstream's Scanner.type_to_string.
  def self.to_name(type) = ALL.include?(type) ? type.to_s : SINGLE.to_s

  # Upstream's Scanner.type_from_string, which warns and falls back to SINGLE
  # for anything it does not recognise.
  def self.from_name(name)
    ALL.find { |type| type.to_s == name.to_s }.then do |type|
      if type.nil?
        warn "Unknown ScanType: #{name}. Please report this error."
        SINGLE
      else
        type
      end
    end
  end
end

# ScanSide mirrors upstream's ScanSide enumeration. The names are the nicks of
# the org.gnome.SimpleScan.PageSide GSettings enum.
module ScanSide
  FRONT = :front
  BACK = :back
  BOTH = :both
  ALL = [FRONT, BACK, BOTH].freeze

  def self.to_name(side) = ALL.include?(side) ? side.to_s : BOTH.to_s

  def self.from_name(name) = ALL.find { |side| side.to_s == name.to_s } || BOTH
end

# ScanDevice is one scanner the backend offered.
class ScanDevice
  attr_accessor :name, :label

  def initialize(name: '', label: '')
    @name = name
    @label = label
  end
end

# ScanPageInfo describes the page a scanner is about to deliver.
class ScanPageInfo
  attr_accessor :width, :height, :depth, :n_channels, :dpi, :device

  def initialize(width: 0, height: 0, depth: 8, n_channels: 1, dpi: 0.0, device: nil)
    @width = width
    @height = height
    @depth = depth
    @n_channels = n_channels
    @dpi = dpi
    @device = device
  end
end

# ScanLine is one packet of raw scan data.
#
# Upstream carries the data as a uchar array with a separate data_length; here
# the data is a binary String and data_length is the length of one line within
# it, which is what Page#parse_scan_line indexes with.
class ScanLine
  attr_accessor :number, :n_lines, :width, :depth, :channel, :data, :data_length

  def initialize(number: 0, n_lines: 1, width: 0, depth: 8, channel: -1, data: '', data_length: 0)
    @number = number
    @n_lines = n_lines
    @width = width
    @depth = depth
    @channel = channel
    @data = data
    @data_length = data_length
  end
end

# ScanOptions is the request the window hands to the scanner.
class ScanOptions
  attr_accessor :dpi,
    :scan_mode,
    :depth,
    :type,
    :side,
    :paper_width,
    :paper_height,
    :brightness,
    :contrast,
    :page_delay

  def initialize
    @dpi = 0
    @scan_mode = ScanMode::DEFAULT
    @depth = 8
    @type = ScanType::SINGLE
    @side = ScanSide::BOTH
    @paper_width = 0
    @paper_height = 0
    @brightness = 0
    @contrast = 0
    @page_delay = 0
  end
end
