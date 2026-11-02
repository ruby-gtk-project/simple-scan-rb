# frozen_string_literal: true

require 'zlib'
require 'securerandom'
require 'gtk4'

require_relative 'page'
require_relative 'simple/scan/rb/version'

# Book is the ordered list of scanned pages, and the saver that writes them
# out as PNG, JPEG or PDF.
#
# Ported from upstream's src/book.vala, which holds Book, BookSaver, PDFWriter
# and make_indexed_file. Upstream spreads the encoding over a thread pool with
# a separate writer thread; here one page is encoded per main-loop idle turn,
# which keeps the window responsive and the cancel button live without the
# queues and mutexes, and keeps the pages in order by construction.
class Book
  include Signals

  def initialize
    @pages = []
  end

  def n_pages = @pages.length

  def pages = @pages.dup

  def clear
    @pages.each { |page| disconnect_page(page) }
    @pages = []
    emit(:cleared)
  end

  def append_page(page)
    connect_page(page)
    @pages.push(page)
    emit(:page_added, page)
    emit(:changed)
  end

  def move_page(page, location)
    @pages.delete(page)
    @pages.insert(location, page)
    emit(:reordered)
    emit(:changed)
  end

  def reverse
    @pages = @pages.reverse
    emit(:reordered)
    emit(:changed)
  end

  # Interleave the front pages with the back pages, which arrive as a second
  # pass through the feeder.
  def combine_sides
    n_front = n_pages - (n_pages / 2)
    @pages = n_pages.times.map do |i|
      i.even? ? @pages[i / 2] : @pages[n_front + (i / 2)]
    end
    emit(:reordered)
    emit(:changed)
  end

  # The same, for a second pass that came back through the feeder reversed.
  def combine_sides_reverse
    @pages = n_pages.times.map do |i|
      i.even? ? @pages[i / 2] : @pages[n_pages - 1 - (i / 2)]
    end
    emit(:reordered)
    emit(:changed)
  end

  def delete_page(page)
    page.then do |target|
      unless target.nil?
        disconnect_page(target)
        @pages.delete(target)
        emit(:page_removed, target)
        emit(:changed)
      end
    end
  end

  def get_page(page_number)
    (page_number.negative? ? @pages.length + page_number : page_number).then do |index|
      @pages[index]
    end
  end

  def get_page_index(page) = @pages.index(page)

  # Saves the book, one page per main-loop turn.
  #
  # on_progress is handed a fraction the same way upstream's
  # ProgressionCallback is; on_finished is handed nil, or the exception that
  # stopped the save. A cancelled save finishes with nil, as upstream's does.
  def save_async(mime_type:, quality:, path:, on_progress: nil, on_finished: nil, cancellable: nil)
    BookSaver.new(
      book:        self,
      mime_type:   mime_type,
      quality:     quality,
      path:        path,
      on_progress: on_progress,
      on_finished: on_finished,
      cancellable: cancellable,
    ).tap(&:start)
  end

  private

    # Upstream connects page_changed_cb to both signals and disconnects the
    # same callback later; here the handler each connect returned is kept so
    # the same pair can be handed back to Page#off.
    WATCHED_PAGE_SIGNALS = [:pixels_changed, :crop_changed].freeze

    def connect_page(page)
      handler_table[page] = WATCHED_PAGE_SIGNALS.to_h do |name|
        [name, page.on(name) { emit(:changed) }]
      end
    end

    def disconnect_page(page)
      handler_table.fetch(page, {}).each { |name, handler| page.off(name, handler) }
      handler_table.delete(page)
    end

    def handler_table
      @handler_table ||= {}
    end
end

# The filename for page i of n: unchanged for a single page, and otherwise the
# index inserted before the extension, zero-padded to the width of n.
#
# Upstream's make_indexed_file, which works in URIs; this works in paths,
# because that is what the save dialog in this port hands back.
def make_indexed_file(path, index, n_pages)
  if n_pages == 1
    path.to_s
  else
    File.extname(path.to_s).then do |suffix|
      prefix = path.to_s[0, path.to_s.length - suffix.length]
      format(
        "%s-%0#{n_pages.to_s.length}d%s",
        prefix,
        index + 1,
        suffix,
      )
    end
  end
end

# BookSaver encodes and writes a book.
#
# Ported from upstream's private BookSaver class. One page is encoded and
# written per idle turn; the PDF objects are numbered up front exactly as
# upstream numbers them, so the pages can be streamed out in order as they are
# encoded rather than collected and sorted.
class BookSaver
  def initialize(book:, mime_type:, quality:, path:, on_progress:, on_finished:, cancellable:)
    @book = book
    @mime_type = mime_type
    @quality = quality
    @path = path.to_s
    @on_progress = on_progress
    @on_finished = on_finished
    @cancellable = cancellable
    @n_pages = book.n_pages
    @index = 0
    @progression = 0.0
  end

  def start
    if @mime_type == 'application/pdf'
      start_pdf
    else
      @stream = nil
    end
    GLib::Idle.add { save_next_page }
  end

  private

    def cancelled? = !@cancellable.nil? && @cancellable.cancelled?

    # One page per turn. Returning false takes the idle source off the loop.
    def save_next_page
      if cancelled?
        finish(nil)
        false
      elsif @index >= @n_pages
        finish_document
        false
      else
        write_page(@index)
        @index += 1
        update_progression
        true
      end
    rescue StandardError, GLib::Error => e
      finish(e)
      false
    end

    def write_page(index)
      @book.get_page(index).then do |page|
        if @mime_type == 'application/pdf'
          write_pdf_page(index, page)
        else
          write_image_page(index, page)
        end
      end
    end

    def finish_document
      if @mime_type == 'application/pdf'
        finish_pdf
      end
      update_progression
      finish(nil)
    end

    def finish(error)
      @stream&.close
      @stream = nil
      @on_finished&.call(error)
    end

    def update_progression
      @progression += 1.0 / (@n_pages + 1)
      @on_progress&.call(@progression)
    end

    # PNG and JPEG are one file per page, with the index in the filename.
    def write_image_page(index, page)
      page.get_image(true).then do |image|
        if @mime_type == 'image/jpeg'
          image.save(make_indexed_file(@path, index, @n_pages), 'jpeg', page.jpeg_options(@quality))
        else
          image.save(make_indexed_file(@path, index, @n_pages), 'png', page.png_options)
        end
      end
    end

    # PDF
    #
    # The object numbers are allocated in upstream's order: catalog, metadata,
    # pages, info, then three per page, then the structure tree root.
    def start_pdf
      @writer = PDFWriter.new(File.open(@path, 'wb'))
      @stream = @writer.stream
      @catalog_number = @writer.add_object
      @metadata_number = @writer.add_object
      @pages_number = @writer.add_object
      @info_number = @writer.add_object
      @page_numbers = Array.new(@n_pages) { [@writer.add_object, @writer.add_object, @writer.add_object] }
      @struct_tree_root_number = @writer.add_object

      write_pdf_header
    end

    def write_pdf_header
      @writer.write_string("%PDF-1.3\n")
      @writer.write_string("%\xe2\xe3\xcf\xd3\n")
      write_pdf_catalog
      write_pdf_metadata
      write_pdf_pages
    end

    def write_pdf_catalog
      @writer.start_object(@catalog_number)
      @writer.write_string("#{@catalog_number} 0 obj\n")
      @writer.write_string("<<\n")
      @writer.write_string("/Type /Catalog\n")
      @writer.write_string("/Metadata #{@metadata_number} 0 R\n")
      @writer.write_string("/MarkInfo << /Marked true >>\n")
      @writer.write_string("/StructTreeRoot #{@struct_tree_root_number} 0 R\n")
      @writer.write_string("/Pages #{@pages_number} 0 R\n")
      @writer.write_string(">>\n")
      @writer.write_string("endobj\n")
    end

    # The XMP packet, with the id the PDF/A spec fixes.
    def write_pdf_metadata
      pdf_metadata.then do |metadata|
        @writer.write_string("\n")
        @writer.start_object(@metadata_number)
        @writer.write_string("#{@metadata_number} 0 obj\n")
        @writer.write_string("<<\n")
        @writer.write_string("/Type /Metadata\n")
        @writer.write_string("/Subtype /XML\n")
        @writer.write_string("/Length #{metadata.bytesize}\n")
        @writer.write_string(">>\n")
        @writer.write_string("stream\n")
        @writer.write_string(metadata)
        @writer.write_string("\n")
        @writer.write_string("endstream\n")
        @writer.write_string("endobj\n")
      end
    end

    def pdf_metadata
      Time.now.strftime('%Y-%m-%dT%H:%M:%S%:z').then do |date|
        <<~XMP.chomp
          <?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                   xmlns:xmp="http://ns.adobe.com/xap/1.0/">
            <rdf:Description rdf:about=""
                             xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/"
                             xmlns:xmp="http://ns.adobe.com/xap/1.0/">
              <pdfaid:part>1</pdfaid:part>
              <pdfaid:conformance>A</pdfaid:conformance>
              <xmp:CreatorTool>Simple Scan #{Simple::Scan::Rb::VERSION}</xmp:CreatorTool>
              <xmp:CreateDate>#{date}</xmp:CreateDate>
              <xmp:ModifyDate>#{date}</xmp:ModifyDate>
              <xmp:MetadataDate>#{date}</xmp:MetadataDate>
            </rdf:Description>
          </rdf:RDF>
          <?xpacket end="w"?>
        XMP
      end
    end

    def write_pdf_pages
      @writer.write_string("\n")
      @writer.start_object(@pages_number)
      @writer.write_string("#{@pages_number} 0 obj\n")
      @writer.write_string("<<\n")
      @writer.write_string("/Type /Pages\n")
      @writer.write_string('/Kids [')
      @page_numbers.each { |numbers| @writer.write_string(" #{numbers[0]} 0 R") }
      @writer.write_string(" ]\n")
      @writer.write_string("/Count #{@n_pages}\n")
      @writer.write_string(">>\n")
      @writer.write_string("endobj\n")
    end

    def write_pdf_page(index, page)
      encode_pdf_image(page).then do |encoded|
        write_pdf_page_object(index, encoded)
        write_pdf_page_image(index, encoded)
        write_pdf_struct_tree_root
        write_pdf_page_contents(index, encoded)
      end
    end

    def write_pdf_page_object(index, encoded)
      @page_numbers[index].then do |(page_number, image_number, content_number)|
        @writer.write_string("\n")
        @writer.start_object(page_number)
        @writer.write_string("#{page_number} 0 obj\n")
        @writer.write_string("<<\n")
        @writer.write_string("/Type /Page\n")
        @writer.write_string("/Parent #{@pages_number} 0 R\n")
        @writer.write_string("/Resources << /XObject << /Im#{index} #{image_number} 0 R >> >>\n")
        @writer.write_string(
          format("/MediaBox [ 0 0 %.2f %.2f ]\n", encoded[:page_width], encoded[:page_height]),
        )
        @writer.write_string("/Contents #{content_number} 0 R\n")
        @writer.write_string(">>\n")
        @writer.write_string("endobj\n")
      end
    end

    def write_pdf_page_image(index, encoded)
      @page_numbers[index][1].then do |image_number|
        @writer.write_string("\n")
        @writer.start_object(image_number)
        @writer.write_string("#{image_number} 0 obj\n")
        @writer.write_string("<<\n")
        @writer.write_string("/Type /XObject\n")
        @writer.write_string("/Subtype /Image\n")
        @writer.write_string("/Width #{encoded[:width]}\n")
        @writer.write_string("/Height #{encoded[:height]}\n")
        @writer.write_string("/ColorSpace /#{encoded[:color_space]}\n")
        @writer.write_string("/BitsPerComponent #{encoded[:depth]}\n")
        @writer.write_string("/Length #{encoded[:data].bytesize}\n")
        @writer.write_string("/Filter /#{encoded[:filter]}\n")
        @writer.write_string(">>\n")
        @writer.write_string("stream\n")
        @writer.write(encoded[:data])
        @writer.write_string("\n")
        @writer.write_string("endstream\n")
        @writer.write_string("endobj\n")
      end
    end

    def write_pdf_struct_tree_root
      @writer.write_string("\n")
      @writer.start_object(@struct_tree_root_number)
      @writer.write_string("#{@struct_tree_root_number} 0 obj\n")
      @writer.write_string("<<\n")
      @writer.write_string("/Type /StructTreeRoot\n")
      @writer.write_string(">>\n")
      @writer.write_string("endobj\n")
    end

    def write_pdf_page_contents(index, encoded)
      format(
        "q\n%f 0 0 %f 0 0 cm\n/Im%d Do\nQ",
        encoded[:page_width],
        encoded[:page_height],
        index,
      ).then do |command|
        @page_numbers[index][2].then do |content_number|
          @writer.write_string("\n")
          @writer.start_object(content_number)
          @writer.write_string("#{content_number} 0 obj\n")
          @writer.write_string("<<\n")
          @writer.write_string("/Length #{command.bytesize}\n")
          @writer.write_string(">>\n")
          @writer.write_string("stream\n")
          @writer.write_string(command)
          @writer.write_string("\n")
          @writer.write_string("endstream\n")
          @writer.write_string("endobj\n")
        end
      end
    end

    def finish_pdf
      write_pdf_info
      write_pdf_xref.then { |xref_offset| write_pdf_trailer(xref_offset) }
    end

    def write_pdf_info
      @writer.write_string("\n")
      @writer.start_object(@info_number)
      @writer.write_string("#{@info_number} 0 obj\n")
      @writer.write_string("<<\n")
      @writer.write_string("/Creator (Simple Scan #{Simple::Scan::Rb::VERSION})\n")
      @writer.write_string(">>\n")
      @writer.write_string("endobj\n")
    end

    def write_pdf_xref
      @writer.write_string("\n")
      @writer.offset.tap do |xref_offset|
        @writer.write_string("xref\n")
        @writer.write_string("0 #{@writer.object_offsets.length + 1}\n")
        @writer.write_string(format("%010d 65535 f \n", @writer.next_empty_object(0)))
        @writer.object_offsets.each_with_index do |offset, i|
          if offset.zero?
            @writer.write_string(format("%010d 65535 f \n", @writer.next_empty_object(i + 1)))
          else
            @writer.write_string(format("%010d 00000 n \n", offset))
          end
        end
      end
    end

    def write_pdf_trailer(xref_offset)
      pdf_id.then do |id|
        @writer.write_string("\n")
        @writer.write_string("trailer\n")
        @writer.write_string("<<\n")
        @writer.write_string("/Size #{@writer.object_offsets.length + 1}\n")
        @writer.write_string("/Info #{@info_number} 0 R\n")
        @writer.write_string("/Root #{@catalog_number} 0 R\n")
        @writer.write_string("/ID [<#{id}> <#{id}>]\n")
        @writer.write_string(">>\n")
        @writer.write_string("startxref\n")
        @writer.write_string("#{xref_offset}\n")
        @writer.write_string("%%EOF\n")
      end
    end

    def pdf_id
      @pdf_id ||= SecureRandom.hex(16)
    end

    # One page's image, as the stream a PDF /Image XObject wants: the raw
    # samples deflated, or the JPEG, whichever came out smaller — the same
    # choice upstream makes, for the same reason.
    def encode_pdf_image(page)
      page.get_image(true).then do |image|
        pdf_samples(page, image).then do |(data, color_space, depth)|
          image.save('jpeg', page.jpeg_options(@quality)).then do |jpeg_data|
            pick_pdf_filter(data, jpeg_data).then do |(stream_data, filter)|
              {
                data:        stream_data,
                filter:      filter,
                width:       image.width,
                height:      image.height,
                color_space: color_space,
                depth:       depth,
                page_width:  image.width * 72.0 / page.dpi,
                page_height: image.height * 72.0 / page.dpi,
              }
            end
          end
        end
      end
    end

    def pick_pdf_filter(data, jpeg_data)
      Zlib::Deflate.deflate(data, Zlib::BEST_COMPRESSION).then do |zlib_data|
        if zlib_data.bytesize < jpeg_data.bytesize
          [zlib_data, 'FlateDecode']
        else
          [jpeg_data, 'DCTDecode']
        end
      end
    end

    # The raw samples for the page, at the depth the page was scanned in:
    # 8-bit RGB for colour, and 1, 2 or 8 bit grey otherwise.
    def pdf_samples(page, image)
      if page.color?
        [rgb_samples(image), 'DeviceRGB', 8]
      elsif page.depth == 2
        [two_bit_samples(image), 'DeviceGray', 2]
      elsif page.depth == 1
        [one_bit_samples(image), 'DeviceGray', 1]
      else
        [gray_samples(image), 'DeviceGray', 8]
      end
    end

    def image_rows(image)
      image.read_pixel_bytes.to_s.then do |pixels|
        image.height.times.map { |row| pixels.byteslice(row * image.rowstride, image.width * 3).to_s }
      end
    end

    def rgb_samples(image) = image_rows(image).join

    def gray_samples(image)
      image_rows(image).map { |row| row.unpack('C*').each_slice(3).map(&:first).pack('C*') }.join
    end

    # Two bits per sample, four to a byte, each row padded to a byte boundary.
    def two_bit_samples(image)
      image_rows(image).map do |row|
        row.unpack('C*').each_slice(3).map { |(red, _green, _blue)| quantize_two_bit(red) }
          .each_slice(4).map { |samples| pack_two_bit(samples) }.join
      end.join
    end

    def quantize_two_bit(sample)
      if sample >= 192
        3
      elsif sample >= 128
        2
      elsif sample >= 64
        1
      else
        0
      end
    end

    def pack_two_bit(samples)
      [6, 4, 2, 0].each_with_index.sum { |shift, i| (samples[i] || 0) << shift }.chr
    end

    # One bit per sample, eight to a byte, each row padded to a byte boundary.
    def one_bit_samples(image)
      image_rows(image).map do |row|
        row.unpack('C*').each_slice(3).map { |(red, _green, _blue)| red.zero? ? '0' : '1' }
          .each_slice(8).map { |bits| bits.join.ljust(8, '0') }.join.then { |bits| [bits].pack('B*') }
      end.join
    end
end

# PDFWriter counts the bytes it has written, so the cross-reference table can
# name the offset of every object.
#
# Ported from upstream's private PDFWriter class.
class PDFWriter
  attr_reader :offset, :object_offsets, :stream

  def initialize(stream)
    @stream = stream
    @offset = 0
    @object_offsets = []
  end

  def write(data)
    binary(data).then do |bytes|
      @stream.write(bytes)
      @offset += bytes.bytesize
    end
  rescue SystemCallError => e
    warn "Error writing PDF: #{e.message}"
  end

  def write_string(text) = write(text)

  def add_object
    @object_offsets.push(0)
    @object_offsets.length
  end

  def start_object(index)
    @object_offsets[index - 1] = @offset
  end

  # The next object slot that was allocated but never written, which is what a
  # free entry in the cross-reference table points at.
  def next_empty_object(start)
    (start...@object_offsets.length).find { |i| @object_offsets[i].zero? }.then do |index|
      index.nil? ? 0 : index + 1
    end
  end

  private

    def binary(data) = data.dup.force_encoding(Encoding::BINARY)
end
