# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative 'book'
require_relative 'page_view'

# BookView lays the book's pages out left to right in a drawing area, with a
# horizontal scrollbar when they do not fit.
#
# Ported from upstream's src/book-view.vala. The layout arithmetic and the
# keyboard and pointer behaviour are upstream's; the plumbing is GTK4's, so
# the GTK3 event masks and *_event signals become a click gesture, a motion
# controller and a key controller, and the GTK3 focus ring drawn with
# render_focus becomes a dashed rectangle around the selected page.
class BookView < Gtk::Box
  include Signals

  SPACING = 12
  FALLBACK_RULER_COLOR = '#00ff00'

  attr_reader :book

  def initialize(book)
    super(:vertical, 0)
    @book = book
    @page_data = {}
    @need_layout = true
    @laying_out = false
    @show_selected_page = false
    @selected_page_view = nil
    @book_handlers = {}
  end

  def build
    tap do |view|
      view.append(drawing_area)
      view.append(scroll)

      drawing_area.tap do |area|
        area.set_draw_func { |_a, context, width, height| draw(context, width, height) }
        area.add_controller(click_gesture)
        area.add_controller(secondary_gesture)
        area.add_controller(motion_controller)
        area.add_controller(key_controller)
        area.add_controller(focus_controller)

        click_gesture.tap do |gesture|
          gesture.signal_connect('pressed') { |_g, n_press, x, y| pressed(n_press, x, y) }
          gesture.signal_connect('released') { |_g, _n_press, x, y| released(x, y) }
        end

        secondary_gesture.signal_connect('pressed') { |_g, _n_press, x, y| emit(:show_menu, x, y) }
        motion_controller.signal_connect('motion') { |_c, x, y| moved(x, y) }
        key_controller.signal_connect('key-pressed') { |_c, keyval, _code, _state| key_pressed(keyval) }

        focus_controller.tap do |controller|
          controller.signal_connect('enter') { focus_changed }
          controller.signal_connect('leave') { focus_changed }
        end
      end

      scroll.tap do |bar|
        bar.adjustment = adjustment

        adjustment.signal_connect('value-changed') { scroll_changed }
      end

      watch_book
      load_existing_pages
    end
  end

  # Memoized widget methods

  def drawing_area
    @drawing_area ||= Gtk::DrawingArea.new.tap do |area|
      area.set_size_request(200, 100)
      area.can_focus = true
      area.focusable = true
      area.vexpand = true
    end
  end

  def scroll = @scroll ||= Gtk::Scrollbar.new(:horizontal)

  def adjustment = @adjustment ||= Gtk::Adjustment.new(
    0,
    0,
    0,
    1,
    10,
    0,
  )

  def click_gesture = @click_gesture ||= Gtk::GestureClick.new.tap { |gesture| gesture.button = 1 }

  def secondary_gesture = @secondary_gesture ||= Gtk::GestureClick.new.tap { |gesture| gesture.button = 3 }

  def motion_controller = @motion_controller ||= Gtk::EventControllerMotion.new

  def key_controller = @key_controller ||= Gtk::EventControllerKey.new

  def focus_controller = @focus_controller ||= Gtk::EventControllerFocus.new

  def x_offset = adjustment.value.to_i

  def x_offset=(value)
    adjustment.value = value
  end

  def selected_page = @selected_page_view&.page

  def selected_page=(page)
    unless selected_page.equal?(page)
      select_page_view(page.nil? ? nil : @page_data[page])
    end
  end

  def select_next_page
    select_page_view(next_page_view(@selected_page_view))
  end

  def select_prev_page
    select_page_view(prev_page_view(@selected_page_view))
  end

  def redraw
    drawing_area.queue_draw
  end

  private

    def watch_book
      @book_handlers = {
        page_added:   @book.on(:page_added) { |page| page_added(page) },
        page_removed: @book.on(:page_removed) { |page| page_removed(page) },
        reordered:    @book.on(:reordered) { reordered },
        cleared:      @book.on(:cleared) { cleared },
      }
    end

    def load_existing_pages
      @book.pages.each { |page| page_added(page) }
      self.selected_page = @book.get_page(0)
    end

    def page_views = @book.pages.map { |page| @page_data[page] }.compact

    def page_at_index(index) = @page_data[@book.get_page(index)]

    def next_page_view(view)
      page_views.then do |views|
        views.index(view).then do |index|
          index.nil? ? view : (views[index + 1] || view)
        end
      end
    end

    def prev_page_view(view)
      page_views.then do |views|
        views.index(view).then do |index|
          index.nil? || index.zero? ? view : views[index - 1]
        end
      end
    end

    # The theme's foreground colour, which PageView draws its border and
    # rulers in. Upstream warns and falls back to a bright green when the
    # theme has no theme_fg_color, so that a theme author notices.
    def ruler_color
      @ruler_color ||= Gdk::RGBA.parse(FALLBACK_RULER_COLOR).then do |fallback|
        style_color || fallback
      end
    end

    def style_color
      color_from_style
    rescue StandardError
      warn "Couldn't get the theme foreground colour, needed to draw the page view ruler"
      nil
    end

    def color_from_style
      if Adwaita::StyleManager.default.dark?
        Gdk::RGBA.parse('#ffffff')
      else
        Gdk::RGBA.parse('#000000')
      end
    end

    def page_added(page)
      PageView.new(page, ruler_color).tap do |view|
        view.on(:changed) { redraw }
        view.on(:size_changed) { page_view_size_changed }
        @page_data[page] = view
        @need_layout = true
        redraw
      end
    end

    def page_view_size_changed
      @need_layout = true
      redraw
    end

    def page_removed(page)
      replacement_selection(page).then do |new_selection|
        @page_data[page].then do |view|
          unless view.nil?
            view.disconnect
            @page_data.delete(page)
          end
        end

        select_page_view(new_selection)
        @need_layout = true
        redraw
      end
    end

    # Upstream picks the previous page, or the next one when the page being
    # removed was the first.
    def replacement_selection(page)
      if page.equal?(selected_page)
        prev_page_view(@selected_page_view).then do |previous|
          previous.equal?(@selected_page_view) ? next_page_view(@selected_page_view) : previous
        end.tap { @selected_page_view = nil }
      else
        @selected_page_view
      end
    end

    def reordered
      @need_layout = true
      redraw
    end

    def cleared
      @page_data.each_value(&:disconnect)
      @page_data.clear
      @selected_page_view = nil
      emit(:page_selected, nil)
      @need_layout = true
      redraw
    end

    def set_selected_page_view(view)
      unless @selected_page_view.nil? || view.equal?(@selected_page_view)
        @selected_page_view.selected = false
      end

      @selected_page_view = view
      unless @selected_page_view.nil?
        @selected_page_view.selected = drawing_area.has_focus?
      end
    end

    def select_page_view(view)
      unless @selected_page_view.equal?(view)
        set_selected_page_view(view)

        if @need_layout
          @show_selected_page = true
        else
          show_page_view(view)
        end

        emit(:page_selected, view&.page)
      end
    end

    # Scrolls just far enough to bring a page fully into view.
    def show_page_view(view)
      (!view.nil? && scroll.visible?).then do |scrollable|
        if scrollable
          drawing_area.width.then do |allocated_width|
            if view.x_offset - x_offset < 0
              self.x_offset = view.x_offset
            elsif view.x_offset + view.width - x_offset > allocated_width
              self.x_offset = view.x_offset + view.width - allocated_width
            end
          end
        end
      end
    end

    # Upstream's layout_into: scale every page to a common DPI, then fit the
    # tallest or widest of them to the area, and place them in a row.
    def layout_into(width, height)
      page_views.then do |views|
        if views.empty?
          [0, 0]
        else
          place_pages(views, width, height)
        end
      end
    end

    def place_pages(views, width, height)
      max_dpi = views.map { |view| view.page.dpi }.max
      max_width, max_height = scaled_extents(views, max_dpi)
      fit_by_width = max_width.to_f / [max_height, 1].max > width.to_f / [height, 1].max

      views.each { |view| size_page(
        view,
        max_dpi,
        max_width,
        max_height,
        width,
        height,
        fit_by_width,
      ) }
      position_pages(views, height)
    end

    def scaled_extents(views, max_dpi)
      views.map do |view|
        page = view.page
        [
          ((page.width.to_f * max_dpi / [page.dpi, 1].max) + 0.5).to_i,
          ((page.height.to_f * max_dpi / [page.dpi, 1].max) + 0.5).to_i,
        ]
      end.then { |sizes| [sizes.map(&:first).max, sizes.map(&:last).max] }
    end

    def size_page(view, max_dpi, max_width, max_height, width, height, fit_by_width)
      page = view.page
      if fit_by_width
        view.width = (page.width.to_f * max_dpi * width / ([page.dpi, 1].max * [max_width, 1].max)).to_i
      else
        view.height = (page.height.to_f * max_dpi * height / ([page.dpi, 1].max * [max_height, 1].max)).to_i
      end
    end

    def position_pages(views, height)
      book_width = 0
      book_height = 0

      views.each do |view|
        view.x_offset = book_width
        view.y_offset = (height - view.height) / 2
        book_height = [book_height, view.height].max
        book_width += view.width + SPACING
      end

      [book_width - SPACING, book_height]
    end

    # Upstream's layout: try without a scrollbar, and lay out again with one
    # when the pages do not fit.
    def layout
      @need_layout.then do |needed|
        if needed
          @laying_out = true
          relayout
          @need_layout = false
          @show_selected_page = false
          @laying_out = false
        end
      end
    end

    def relayout
      right_aligned = adjustment.value >= adjustment.upper - adjustment.page_size
      width = drawing_area.width
      height = height_for_layout

      layout_into(width, height).then do |(book_width, _book_height)|
        if book_width > width
          layout_into(width, drawing_area.height).then { |(scrolled_width, _)| show_scrollbar(scrolled_width, width, right_aligned) }
        else
          hide_scrollbar(book_width, width)
        end
      end

      if @show_selected_page
        show_page_view(@selected_page_view)
      end
    end

    def height_for_layout = [height - scroll.height, drawing_area.height].max

    def show_scrollbar(book_width, allocated_width, right_aligned)
      adjustment.lower = 0
      adjustment.upper = book_width
      adjustment.page_size = allocated_width

      (book_width - allocated_width).then do |max_offset|
        if right_aligned || x_offset > max_offset
          self.x_offset = max_offset
        end
      end

      scroll.visible = true
    end

    def hide_scrollbar(book_width, allocated_width)
      scroll.visible = false
      ((book_width - allocated_width) / 2).then do |offset|
        adjustment.lower = offset
        adjustment.upper = offset
        adjustment.page_size = 0
        self.x_offset = offset
      end
    end

    def draw(context, _width, _height)
      layout
      page_views.each { |view| draw_page(context, view) }
    end

    def draw_page(context, view)
      context.save
      context.translate(-x_offset, 0)
      view.render(context)
      context.restore

      if view.selected?
        draw_focus(context, view)
      end
    end

    # GTK4 has no render_focus, so the focus ring upstream asks the style
    # context for is drawn here as a dashed rectangle around the page.
    def draw_focus(context, view)
      context.save
      context.set_source_rgba(
        0.4,
        0.4,
        0.4,
        0.9,
      )
      context.set_line_width(1)
      context.set_dash([2, 2], 0)
      context.rectangle(
        view.x_offset - x_offset + 0.5,
        view.y_offset + 0.5,
        view.width - 1,
        view.height - 1,
      )
      context.stroke
      context.restore
    end

    # The page under a point in drawing-area coordinates, with the point
    # expressed relative to that page.
    def page_at(x, y)
      page_views.find do |view|
        x >= view.x_offset && x <= view.x_offset + view.width &&
          y >= view.y_offset && y <= view.y_offset + view.height
      end.then do |view|
        view.nil? ? nil : [view, x - view.x_offset, y - view.y_offset]
      end
    end

    def pressed(n_press, x, y)
      layout
      drawing_area.grab_focus

      page_at(x.to_i + x_offset, y.to_i).then do |hit|
        select_page_view(hit&.first)

        unless @selected_page_view.nil?
          if n_press >= 2
            emit(:show_page, selected_page)
          else
            @selected_page_view.button_press(hit[1], hit[2])
          end
        end
      end
    end

    def released(x, y)
      unless @selected_page_view.nil?
        @selected_page_view.button_release(
          x.to_i + x_offset - @selected_page_view.x_offset,
          y.to_i - @selected_page_view.y_offset,
        )
      end
    end

    def moved(x, y)
      dragging?.then do |dragging|
        if dragging
          drag_selected_page(x, y)
        else
          hover(x, y)
        end
      end
    end

    def dragging? = click_gesture.active? && !@selected_page_view.nil?

    def drag_selected_page(x, y)
      @selected_page_view.motion(
        x.to_i + x_offset - @selected_page_view.x_offset,
        y.to_i - @selected_page_view.y_offset,
      )
      drawing_area.set_cursor_from_name(@selected_page_view.cursor)
    end

    def hover(x, y)
      page_at(x.to_i + x_offset, y.to_i).then do |hit|
        if hit.nil?
          drawing_area.set_cursor_from_name('default')
        else
          hit[0].motion(hit[1], hit[2])
          drawing_area.set_cursor_from_name(hit[0].cursor)
        end
      end
    end

    # Home/End jump to the ends of the book; Left/Right step through it.
    def key_pressed(keyval)
      case keyval
      when Gdk::Keyval::KEY_Home
        self.selected_page = @book.get_page(0)
        true
      when Gdk::Keyval::KEY_End
        self.selected_page = @book.get_page(@book.n_pages - 1)
        true
      when Gdk::Keyval::KEY_Left
        select_prev_page
        true
      when Gdk::Keyval::KEY_Right
        select_next_page
        true
      else
        false
      end
    end

    def focus_changed
      set_selected_page_view(@selected_page_view)
      redraw
    end

    def scroll_changed
      unless @laying_out
        redraw
      end
    end
end
