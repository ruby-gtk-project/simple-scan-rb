# frozen_string_literal: true

require 'gtk4'

# PageIcon draws a small sheet of paper with a label on it, used by the
# reorder dialog to show which page ends up where.
#
# Ported from upstream's src/page-icon.vala. Upstream overrides the four
# get_preferred_* virtual methods to hold an A4 aspect ratio; GTK4 asks a
# drawing area for its content size instead, so the same ratio is expressed as
# a content width and height, and the draw function re-derives the largest
# A4-shaped rectangle that fits whatever size the icon was actually given.
class PageIcon < Gtk::DrawingArea
  MINIMUM_WIDTH = 20

  def initialize(text, red = 1.0, green = 1.0, blue = 1.0)
    super()
    @text = text
    @red = red
    @green = green
    @blue = blue
    self.content_width = MINIMUM_WIDTH
    self.content_height = (MINIMUM_WIDTH * Math.sqrt(2)).round
    self.valign = :center
    self.halign = :center
  end

  def build
    tap do |icon|
      icon.set_draw_func { |_area, context, width, height| draw(context, width, height) }
    end
  end

  private

    def draw(context, allocated_width, allocated_height)
      sheet_size(allocated_width, allocated_height).then do |(width, height)|
        context.translate((allocated_width - width) / 2, (allocated_height - height) / 2)
        draw_sheet(context, width, height)
        draw_text(context, width, height)
      end
    end

    # The largest rectangle of paper aspect that fits the allocation.
    def sheet_size(allocated_width, allocated_height)
      if allocated_width * Math.sqrt(2) > allocated_height
        [(allocated_height / Math.sqrt(2)).round, allocated_height]
      else
        [allocated_width, (allocated_width * Math.sqrt(2)).round]
      end
    end

    def draw_sheet(context, width, height)
      context.rectangle(
        0.5,
        0.5,
        width - 1,
        height - 1,
      )
      context.set_source_rgb(@red, @green, @blue)
      context.fill_preserve
      context.set_line_width(1.0)
      context.set_source_rgb(0.0, 0.0, 0.0)
      context.stroke
    end

    def draw_text(context, width, height)
      context.text_extents(@text).then do |extents|
        context.translate(((width - extents.width) * 0.5) - 0.5, ((height + extents.height) * 0.5) - 0.5)
        context.show_text(@text)
      end
    end
end
