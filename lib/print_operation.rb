# frozen_string_literal: true

require 'gtk4'

require_relative 'book'

# PrintOperation prints the book, one page per sheet.
#
# Ported from print_document and draw_page in upstream's src/app-window.vala:
# the page is turned to match the sheet's orientation, scaled from its own DPI
# to the printer's, and painted.
class PrintOperation
  def initialize(book, &on_error)
    @book = book
    @on_error = on_error
  end

  def build
    operation.tap do |print|
      print.n_pages = @book.n_pages

      print.signal_connect('draw-page') { |_op, context, page_number| draw_page(context, page_number) }
    end
  end

  def operation = @operation ||= Gtk::PrintOperation.new

  # Runs the print dialog. Errors are reported through the block given to the
  # constructor, which is where upstream's warning goes.
  def run(parent)
    operation.run(:print_dialog, parent)
  rescue GLib::Error => e
    @on_error&.call(e)
  end

  private

    def draw_page(print_context, page_number)
      @book.get_page(page_number).then do |page|
        unless page.nil?
          paint(print_context, page)
        end
      end
    end

    def paint(print_context, page)
      print_context.cairo_context.then do |context|
        rotate_to_match(context, print_context, page)
        context.scale(print_context.dpi_x / page.dpi, print_context.dpi_y / page.dpi)
        context.set_source_pixbuf(page.get_image(true), 0, 0)
        context.paint
      end
    end

    # A landscape page on a portrait sheet, or the other way round, is turned
    # a quarter turn so it fills the sheet.
    def rotate_to_match(context, print_context, page)
      (print_context.width > print_context.height).then do |sheet_is_landscape|
        unless page.landscape? == sheet_is_landscape
          context.translate(print_context.width, 0)
          context.rotate(Math::PI / 2)
        end
      end
    end
end
