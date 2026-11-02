# frozen_string_literal: true

require 'gtk4'

require_relative 'scan_options'

# ScanDirection mirrors upstream's ScanDirection enumeration, which is declared
# in src/page.vala alongside Page itself.
module ScanDirection
  TOP_TO_BOTTOM = :top_to_bottom
  LEFT_TO_RIGHT = :left_to_right
  BOTTOM_TO_TOP = :bottom_to_top
  RIGHT_TO_LEFT = :right_to_left

  # In rotation order, so the index of a direction is how many quarter turns
  # to the left it stands from TOP_TO_BOTTOM. Upstream relies on the ordinal
  # values of the enum for exactly this.
  ALL = [TOP_TO_BOTTOM, LEFT_TO_RIGHT, BOTTOM_TO_TOP, RIGHT_TO_LEFT].freeze

  def self.index(direction) = ALL.index(direction) || 0

  def self.to_name(direction) = direction.to_s.upcase

  def self.from_name(name) = ALL.find { |d| d.to_s.upcase == name.to_s.upcase } || TOP_TO_BOTTOM
end

# Signals gives the model classes the connect/disconnect/emit trio that
# upstream gets from GObject signals for free.
#
# Page and Book are plain Ruby objects rather than GObject subclasses, so the
# handler bookkeeping upstream's `signal` keyword generates is spelled out
# here: #on returns the handler so a caller can hand the same object back to
# #off, which is what upstream's `.disconnect (cb)` does.
module Signals
  def on(name, &handler)
    handlers(name).push(handler)
    handler
  end

  def off(name, handler)
    handlers(name).delete(handler)
    handler
  end

  def emit(name, *args)
    handlers(name).dup.each { |handler| handler.call(*args) }
  end

  private

    def handlers(name)
      @signal_handlers ||= {}
      @signal_handlers[name] ||= []
    end
end

# Page is one scanned page: its raw pixel data, the direction it was scanned
# in, and the crop the user has placed on it.
#
# Ported from upstream's src/page.vala. Two things are done differently from
# the Vala: the pixel buffer is a binary String rather than a uchar array, and
# get_image builds the image in scan orientation and lets GdkPixbuf rotate and
# crop it, instead of reading every pixel back through a get_pixel switch.
# The result is the same image; the work happens in C rather than in Ruby.
class Page
  include Signals

  # Named crop sizes in inches, from set_named_crop.
  NAMED_CROPS = {
    'A3'     => [11.7, 16.5],
    'A4'     => [8.3, 11.7],
    'A5'     => [5.8, 8.3],
    'A6'     => [4.1, 5.8],
    'letter' => [8.5, 11],
    'legal'  => [8.5, 14],
    '4x6'    => [4, 6],
  }.freeze

  # The quarter-turn GdkPixbuf has to apply to scan-space pixels to put them
  # the way up the user asked for.
  ROTATIONS = {
    ScanDirection::TOP_TO_BOTTOM => :none,
    ScanDirection::LEFT_TO_RIGHT => :counterclockwise,
    ScanDirection::BOTTOM_TO_TOP => :upsidedown,
    ScanDirection::RIGHT_TO_LEFT => :clockwise,
  }.freeze

  attr_reader :dpi,
    :depth,
    :scan_width,
    :scan_height,
    :rowstride,
    :n_channels,
    :scan_line,
    :scan_direction,
    :crop_name,
    :crop_x,
    :crop_y,
    :crop_width,
    :crop_height
  attr_accessor :color_profile

  def initialize(width: 0, height: 0, dpi: 0, scan_direction: ScanDirection::TOP_TO_BOTTOM)
    @expected_rows = -1
    @depth = 8
    @n_channels = 1
    @rowstride = 0
    @pixels = String.new('', encoding: Encoding::BINARY)
    @scanning = false
    @has_data = false
    @scan_line = 0
    @has_crop = false
    @crop_name = nil
    @crop_x = 0
    @crop_y = 0
    @crop_width = 0
    @crop_height = 0
    @color_profile = nil
    @dpi = dpi
    @scan_direction = ScanDirection::TOP_TO_BOTTOM

    if upright?(scan_direction)
      @scan_width = width
      @scan_height = height
    else
      @scan_width = height
      @scan_height = width
    end

    self.scan_direction = scan_direction
  end

  # Upstream's Page.from_data constructor, used when restoring an autosave.
  def self.from_data(
    scan_width:,
    scan_height:,
    rowstride:,
    n_channels:,
    depth:,
    dpi:,
    scan_direction:,
    color_profile:,
    pixels:,
    has_crop:,
    crop_name:,
    crop_x:,
    crop_y:,
    crop_width:,
    crop_height:
  )
    new(dpi: dpi).tap do |page|
      page.restore(
        scan_width:     scan_width,
        scan_height:    scan_height,
        rowstride:      rowstride,
        n_channels:     n_channels,
        depth:          depth,
        scan_direction: scan_direction,
        color_profile:  color_profile,
        pixels:         pixels,
        has_crop:       has_crop,
        crop_name:      crop_name,
        crop_x:         crop_x,
        crop_y:         crop_y,
        crop_width:     crop_width,
        crop_height:    crop_height,
      )
    end
  end

  # The body of Page.from_data. Public so the class method above can reach it;
  # nothing else should call it on a page that already holds a scan.
  def restore(
    scan_width:,
    scan_height:,
    rowstride:,
    n_channels:,
    depth:,
    scan_direction:,
    color_profile:,
    pixels:,
    has_crop:,
    crop_name:,
    crop_x:,
    crop_y:,
    crop_width:,
    crop_height:
  )
    @scan_width = scan_width
    @scan_height = scan_height
    @expected_rows = scan_height
    @rowstride = rowstride
    @n_channels = n_channels
    @depth = depth
    @scan_direction = ScanDirection::TOP_TO_BOTTOM
    self.scan_direction = scan_direction
    @color_profile = color_profile
    if pixels.nil?
      @pixels = String.new('', encoding: Encoding::BINARY)
    else
      @pixels = binary(pixels)
    end
    @has_data = !pixels.nil?
    @has_crop = has_crop
    @crop_name = crop_name
    @crop_x = crop_x
    @crop_y = crop_y
    if crop_x + crop_width > scan_width
      @crop_width = scan_width
    else
      @crop_width = crop_width
    end
    if crop_y + crop_height > scan_height
      @crop_height = scan_height
    else
      @crop_height = crop_height
    end
  end

  # Width of the page in pixels after rotation applied.
  def width = upright?(@scan_direction) ? @scan_width : @scan_height

  # Height of the page in pixels after rotation applied.
  def height = upright?(@scan_direction) ? @scan_height : @scan_width

  def landscape? = width > height

  def color? = @n_channels > 1

  def scanning? = @scanning

  def has_data? = @has_data

  def has_crop? = @has_crop

  def pixels = @pixels

  # Rotating the scan rotates the crop with it, and only a quarter turn
  # changes the page's dimensions.
  def scan_direction=(value)
    (value == @scan_direction).then do |unchanged|
      unless unchanged
        left_steps = (ScanDirection.index(value) - ScanDirection.index(@scan_direction)) % 4
        size_has_changed = left_steps != 2

        if @has_crop
          rotate_crop_for(left_steps)
        end

        @scan_direction = value

        if size_has_changed
          emit(:size_changed)
        end
        emit(:scan_direction_changed)
        if @has_crop
          emit(:crop_changed)
        end
      end
    end
  end

  # Upstream's set_page_info: resize the buffer the scanner is about to fill
  # and paint it white (black, for a bitmap, where a set bit is ink).
  def set_page_info(info)
    @expected_rows = info.height
    @dpi = info.dpi.to_i
    @scan_width = info.width
    if info.height < 0
      @scan_height = info.width / 2
    else
      @scan_height = info.height
    end
    @depth = info.depth
    @n_channels = info.n_channels
    @rowstride = ((@scan_width * @depth * @n_channels) + 7) / 8
    @pixels = binary((@depth == 1 ? "\x00" : "\xFF") * (@scan_height * @rowstride))

    emit(:size_changed)
    emit(:pixels_changed)
  end

  def start
    @scanning = true
    emit(:scan_line_changed)
  end

  # Upstream's parse_scan_line, which copies each line of a packet into place
  # and extends the buffer when the scanner delivers more rows than expected.
  def parse_scan_line(line)
    size_has_changed = line.n_lines.times.map { |n| parse_line(line, n) }.any?
    @has_data = true

    if size_has_changed
      emit(:size_changed)
    end
    emit(:scan_line_changed)
    emit(:pixels_changed)
  end

  # Upstream's finish: a page of unknown height is trimmed to the rows that
  # actually arrived.
  def finish
    size_has_changed = false

    if @expected_rows < 0 && @scan_line != @scan_height
      @scan_height = @scan_line
      resize_pixels(@scan_height * @rowstride)
      size_has_changed = true
    end
    @scanning = false

    if size_has_changed
      emit(:size_changed)
    end
    emit(:scan_line_changed)
    emit(:scan_finished)
  end

  def rotate_left
    self.scan_direction = ScanDirection::ALL[(ScanDirection.index(@scan_direction) + 1) % 4]
  end

  def rotate_right
    self.scan_direction = ScanDirection::ALL[(ScanDirection.index(@scan_direction) + 3) % 4]
  end

  def set_no_crop
    @has_crop.then do |had_crop|
      if had_crop
        @has_crop = false
        @crop_name = nil
        @crop_x = 0
        @crop_y = 0
        @crop_width = 0
        @crop_height = 0
        emit(:crop_changed)
      end
    end
  end

  def set_custom_crop(crop_width, crop_height)
    (crop_width >= 1 && crop_height >= 1).then do |valid|
      unchanged = @crop_name.nil? && @has_crop && @crop_width == crop_width && @crop_height == crop_height
      if valid && !unchanged
        @crop_name = nil
        @has_crop = true
        @crop_width = crop_width
        @crop_height = crop_height
        emit(:crop_changed)
      end
    end
  end

  # Upstream's set_named_crop: a paper size in inches, turned the same way up
  # as the page and centred on it.
  def set_named_crop(name)
    NAMED_CROPS[name].then do |size|
      if size.nil?
        warn "Unknown paper size '#{name}'"
      else
        apply_named_crop(name, size)
      end
    end
  end

  def move_crop(x, y)
    (x >= 0 && y >= 0 && x < width && y < height).then do |valid|
      if valid
        @crop_x = x
        @crop_y = y
        emit(:crop_changed)
      end
    end
  end

  # Upstream's rotate_crop: swap the crop's sides, and pull a custom crop back
  # inside the page if the swap pushed it out.
  def rotate_crop
    @has_crop.then do |has_crop|
      if has_crop
        @crop_width, @crop_height = @crop_height, @crop_width
        if @crop_name.nil?
          clip_custom_crop
        end
        emit(:crop_changed)
      end
    end
  end

  # The page as an image, rotated to the scan direction and optionally cropped.
  def get_image(apply_crop)
    rotated_image.then do |image|
      if apply_crop && @has_crop
        crop_rectangle(image).then { |rect| image.subpixbuf(*rect) }
      else
        image
      end
    end
  end

  # The page's colour profile as base64, for the PNG and JPEG icc-profile key.
  def icc_data_encoded
    @color_profile.then do |profile|
      if profile.nil?
        nil
      else
        encode_icc(profile)
      end
    end
  end

  def copy_to_clipboard(window)
    window.display.clipboard.set(Gdk::Texture.new(get_image(true)))
  end

  # Upstream's save_png, used for the "open this page" preview.
  def save_png(path)
    get_image(true).save(path.to_s, 'png', png_options)
  end

  # The key/value pairs GdkPixbuf wants for a PNG of this page.
  def png_options
    { 'x-dpi' => @dpi.to_s, 'y-dpi' => @dpi.to_s }.tap do |options|
      icc_data_encoded.then do |icc|
        unless icc.nil?
          options['icc-profile'] = icc
        end
      end
    end
  end

  # The same, for a JPEG at the given quality.
  def jpeg_options(quality)
    png_options.tap { |options| options['quality'] = quality.to_s }
  end

  private

    def upright?(direction)
      direction == ScanDirection::TOP_TO_BOTTOM || direction == ScanDirection::BOTTOM_TO_TOP
    end

    def binary(string) = string.dup.force_encoding(Encoding::BINARY)

    def resize_pixels(size)
      if @pixels.bytesize < size
        @pixels = binary(@pixels + ((@depth == 1 ? "\x00" : "\xFF") * (size - @pixels.bytesize)))
      else
        @pixels = binary(@pixels.byteslice(0, size))
      end
    end

    # One line of a packet. Returns true when the buffer had to grow, which is
    # what parse_scan_line reports as a size change.
    def parse_line(line, index)
      line_number = line.number + index
      size_changed = false

      while line_number >= @scan_height
        @scan_height += @scan_width / 2
        resize_pixels(@scan_height * @rowstride)
        size_changed = true
      end

      @pixels[line_number * @rowstride, line.data_length] =
        binary(line.data.byteslice(index * line.data_length, line.data_length))
      @scan_line = line_number

      size_changed
    end

    def rotate_crop_for(left_steps)
      case left_steps
      when 1
        x = @crop_x
        @crop_x = @crop_y
        @crop_y = width - (x + @crop_width)
        @crop_width, @crop_height = @crop_height, @crop_width
      when 2
        @crop_x = width - (@crop_x + @crop_width)
        @crop_y = width - (@crop_y + @crop_height)
      when 3
        y = @crop_y
        @crop_y = @crop_x
        @crop_x = height - (y + @crop_height)
        @crop_width, @crop_height = @crop_height, @crop_width
      end
    end

    def apply_named_crop(name, size)
      @crop_name = name
      @has_crop = true

      page_width = width
      page_height = height
      crop_w, crop_h = size
      if page_width > page_height
        crop_w, crop_h = crop_h, crop_w
      end

      @crop_width = (crop_w * @dpi).round
      @crop_height = (crop_h * @dpi).round
      if @crop_width < page_width
        @crop_x = (page_width - @crop_width) / 2
      else
        @crop_x = 0
      end
      if @crop_height < page_height
        @crop_y = (page_height - @crop_height) / 2
      else
        @crop_y = 0
      end
      emit(:crop_changed)
    end

    def clip_custom_crop
      page_width = width
      page_height = height

      if @crop_x + @crop_width > page_width
        @crop_x = page_width - @crop_width
      end
      if @crop_x < 0
        @crop_x = 0
        @crop_width = page_width
      end
      if @crop_y + @crop_height > page_height
        @crop_y = page_height - @crop_height
      end
      if @crop_y < 0
        @crop_y = 0
        @crop_height = page_height
      end
    end

    # The crop, clamped to the page, as GdkPixbuf's x/y/width/height.
    def crop_rectangle(image)
      left = [@crop_x, 0].max
      top = [@crop_y, 0].max
      right = [[@crop_x + @crop_width, image.width].min, left].max
      bottom = [[@crop_y + @crop_height, image.height].min, top].max

      [left, top, [right - left, 1].max, [bottom - top, 1].max]
    end

    def rotated_image
      scan_image.then do |image|
        ROTATIONS.fetch(@scan_direction, :none).then do |rotation|
          rotation == :none ? image : image.rotate(rotation)
        end
      end
    end

    # The raw scan data as an RGB pixbuf, still in scan orientation. A page
    # with no data yet is a white sheet, exactly as upstream renders it.
    def scan_image
      if @has_data && @rowstride.positive?
        rgb_bytes.then do |rgb|
          GdkPixbuf::Pixbuf.new(
            data:            rgb,
            colorspace:      :rgb,
            has_alpha:       false,
            bits_per_sample: 8,
            width:           @scan_width,
            height:          @scan_height,
            rowstride:       @scan_width * 3,
          )
        end
      else
        blank_image
      end
    end

    def blank_image
      GdkPixbuf::Pixbuf.new(
        data:            binary("\xFF" * ([@scan_width, 1].max * [@scan_height, 1].max * 3)),
        colorspace:      :rgb,
        has_alpha:       false,
        bits_per_sample: 8,
        width:           [@scan_width, 1].max,
        height:          [@scan_height, 1].max,
        rowstride:       [@scan_width, 1].max * 3,
      )
    end

    # Scan data in whatever depth and channel count the scanner produced,
    # widened to packed 8-bit RGB. These are the same cases upstream's
    # get_pixel optimises for, taken a row at a time instead of a pixel.
    def rgb_bytes
      if @depth == 8 && @n_channels == 3
        packed_rows(3) { |row| row }
      elsif @depth == 8 && @n_channels == 1
        packed_rows(1) { |row| gray_to_rgb(row.unpack('C*')) }
      elsif @depth == 1
        packed_rows(0) { |row| gray_to_rgb(bitmap_samples(row)) }
      elsif @depth == 2
        packed_rows(0) { |row| gray_to_rgb(two_bit_samples(row)) }
      else
        packed_rows(0) { |row| gray_to_rgb(wide_samples(row)) }
      end
    end

    # Each scan row, trimmed to the page width and handed to the block, joined
    # into one buffer with no padding between rows.
    def packed_rows(bytes_per_pixel)
      String.new('', encoding: Encoding::BINARY, capacity: @scan_height * @scan_width * 3).tap do |out|
        @scan_height.times do |y|
          if bytes_per_pixel.positive?
            row_length = @scan_width * bytes_per_pixel
          else
            row_length = @rowstride
          end
          @pixels.byteslice(y * @rowstride, row_length).then do |row|
            out << pad_row(yield(row.nil? ? '' : row))
          end
        end
      end
    end

    def pad_row(row)
      if row.bytesize < @scan_width * 3
        row + ("\xFF" * ((@scan_width * 3) - row.bytesize))
      else
        row.byteslice(0, @scan_width * 3)
      end
    end

    def gray_to_rgb(samples) = samples.flat_map { |sample| [sample, sample, sample] }.pack('C*')

    # A set bit is ink, so it reads as black.
    def bitmap_samples(row)
      row.unpack1('B*').to_s.byteslice(0, @scan_width).to_s.each_char.map { |bit| bit == '1' ? 0 : 255 }
    end

    def two_bit_samples(row)
      shifts = [6, 4, 2, 0]
      @scan_width.times.map do |x|
        row.getbyte(x / 4).then do |byte|
          byte.nil? ? 255 : ((byte >> shifts[x % 4]) & 0x3) * 255 / 3
        end
      end
    end

    # 16-bit and other wide samples: take the most significant byte of the
    # first channel. Upstream's get_sample never reads these and
    # returns 0xFF.
    def wide_samples(row)
      bytes_per_sample = @depth / 8
      @scan_width.times.map do |x|
        row.getbyte(x * bytes_per_sample * @n_channels).then { |byte| byte.nil? ? 255 : byte }
      end
    end

    # pack('m0') is strict base64 with no line breaks, which is what GLib's
    # Base64.encode produces and what the PNG icc-profile key expects.
    def encode_icc(profile)
      [File.binread(profile)].pack('m0')
    rescue SystemCallError => e
      warn "failed to get icc profile data: #{e.message}"
      nil
    end
end
