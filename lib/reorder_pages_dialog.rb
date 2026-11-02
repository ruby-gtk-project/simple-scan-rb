# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative 'page_icon'

# ReorderPagesDialog offers the four ways a double-sided or reversed scan can
# be put back into reading order, each drawn as a before-and-after row of
# little pages.
#
# Ported from reorder_document, make_reorder_button and make_reorder_box in
# upstream's src/app-window.vala, including the Tango colours it tints the
# page icons with.
class ReorderPagesDialog < Adwaita::Dialog
  # Label, the before-and-after description make_reorder_box reads, and the
  # name of the reordering, in upstream's grid order.
  CHOICES = [
    # Label on button for combining sides in the reordering dialog
    ['Combine sides', 'F1F2F3B1B2B3-F1B1F2B2F3B3', :combine_sides],
    # Label on button for combining sides in reverse order
    ['Combine sides (reverse)', 'F1F2F3B3B2B1-F1B1F2B2F3B3', :combine_sides_reverse],
    # Label on button for reversing in the reordering dialog
    ['Reverse', 'C1C2C3C4C5C6-C6C5C4C3C2C1', :reverse],
    # Label on button for cancelling page reordering
    ['Keep unchanged', 'C1C2C3C4C5C6-C1C2C3C4C5C6', :keep],
  ].freeze

  # Plum for a front side, orange for a back side, from the Tango palette.
  FRONT_COLOR = [0x75 / 255.0, 0x50 / 255.0, 0x7B / 255.0].freeze
  BACK_COLOR = [0xF5 / 255.0, 0x79 / 255.0, 0.0].freeze

  def initialize(&on_choice)
    super()
    @on_choice = on_choice
    # Title of dialog to reorder pages
    self.title = 'Reorder Pages'
    self.content_width = 640
  end

  def build
    tap do |dialog|
      dialog.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = grid

        grid.tap do |layout|
          CHOICES.each_with_index do |(label, items, choice), index|
            layout.attach(
              choice_button(label, items, choice),
              index % 2,
              index / 2,
              1,
              1,
            )
          end
        end
      end
    end
  end

  # Memoized widget methods

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def grid
    @grid ||= Gtk::Grid.new.tap do |layout|
      layout.row_homogeneous = true
      layout.column_homogeneous = true
      layout.row_spacing = 6
      layout.column_spacing = 6
      layout.margin_top = 12
      layout.margin_bottom = 12
      layout.margin_start = 12
      layout.margin_end = 12
    end
  end

  private

    def choice_button(label, items, choice)
      Gtk::Button.new.tap do |button|
        button.child = Gtk::Box.new(:vertical, 6).tap do |box|
          box.append(Gtk::Label.new(label).tap { |text| text.vexpand = true })
          box.append(reorder_box(items).tap { |preview| preview.vexpand = true })
        end

        button.signal_connect('clicked') do
          @on_choice&.call(choice)
          close
        end
      end
    end

    # Upstream's make_reorder_box: the description is read two characters at a
    # time, a side letter and a page number, with "-" drawing the arrow
    # between the before and after groups.
    def reorder_box(items)
      Gtk::Box.new(:horizontal, 6).tap do |box|
        page_box = nil
        pairs(items).each do |pair|
          if pair == '-'
            box.append(Gtk::Label.new('➤'))
            page_box = nil
          else
            page_box = append_page_box(box, page_box)
            page_box.append(page_icon(pair[0], pair[1]))
          end
        end
        box.halign = :center
      end
    end

    # The description split into side/number pairs, with the separator on its
    # own.
    def pairs(items)
      items.scan(/-|../)
    end

    def append_page_box(box, page_box)
      if page_box.nil?
        Gtk::Box.new(:horizontal, 3).tap { |fresh| box.append(fresh) }
      else
        page_box
      end
    end

    def page_icon(side, number)
      paper_color(side, number).then do |(red, green, blue)|
        PageIcon.new(
          number,
          red,
          green,
          blue,
        ).build
      end
    end

    # Upstream mixes each colour with white so the icons look more like paper.
    def paper_color(side, number)
      base_color(side, number).map { |channel| channel + ((1.0 - channel) * 0.7) }
    end

    def base_color(side, number)
      case side
      when 'F'
        FRONT_COLOR
      when 'B'
        BACK_COLOR
      when 'C'
        continuous_color(number)
      else
        [1.0, 1.0, 1.0]
      end
    end

    # Butter through to scarlet red, graded across the six pages.
    def continuous_color(number)
      ((number.to_i - 1) / 5.0).then do |fraction|
        [
          ((0xED / 255.0) * (1 - fraction)) + (0xCC * fraction),
          (0xD4 / 255.0) * (1 - fraction),
          0,
        ]
      end
    end
end
