# frozen_string_literal: true

require 'gtk4'

require_relative 'page'

# CropLocation names the part of the crop rectangle the pointer is over, which
# decides both the cursor and what a drag does.
#
# Ported from the enum of the same name in upstream's src/page-view.vala.
module CropLocation
  NONE = :none
  MIDDLE = :middle
  TOP = :top
  BOTTOM = :bottom
  LEFT = :left
  RIGHT = :right
  TOP_LEFT = :top_left
  TOP_RIGHT = :top_right
  BOTTOM_LEFT = :bottom_left
  BOTTOM_RIGHT = :bottom_right
end

# PageView renders one page into a Cairo context and handles the crop handles.
#
# Ported from upstream's src/page-view.vala. It is not a widget there either —
# BookView lays several of these out and calls render on each.
#
# One thing is done differently. Upstream builds the preview by walking every
# output pixel and area-averaging the source pixels under it, in a 200-line
# set_pixel; here the page hands over a GdkPixbuf and GdkPixbuf scales it
# bilinearly. The result is the same kind of smooth downscale, in C, and the
# partial-scan redraw bookkeeping that existed to keep that loop cheap is no
# longer needed.
class PageView
  include Signals

  RULER_WIDTH = 8
  BORDER_WIDTH = 2
  CROP_BORDER = 20
  MINIMUM_CROP = 15
  ANIMATE_SEGMENTS = 7
  ANIMATE_INTERVAL = 150

  # The cursor name for each crop location, replacing upstream's
  # Gdk.CursorType values, which GTK4 dropped in favour of CSS names.
  CURSORS = {
    CropLocation::MIDDLE       => 'grab',
    CropLocation::TOP          => 'n-resize',
    CropLocation::BOTTOM       => 's-resize',
    CropLocation::LEFT         => 'w-resize',
    CropLocation::RIGHT        => 'e-resize',
    CropLocation::TOP_LEFT     => 'nw-resize',
    CropLocation::TOP_RIGHT    => 'ne-resize',
    CropLocation::BOTTOM_LEFT  => 'sw-resize',
    CropLocation::BOTTOM_RIGHT => 'se-resize',
    CropLocation::NONE         => 'default',
  }.freeze

  attr_reader :page, :cursor, :width, :height
  attr_accessor :x_offset, :y_offset

  def initialize(page, ruler_color)
    @page = page
    @ruler_color = ruler_color
    @image = nil
    @selected = false
    @update_image = true
    @width = 0
    @height = 0
    @x_offset = 0
    @y_offset = 0
    @crop_location = CropLocation::NONE
    @cursor = CURSORS[CropLocation::NONE]
    @animate_segment = 0
    @animate_timeout = nil
    @handlers = {
      pixels_changed:         page.on(:pixels_changed) { page_pixels_changed },
      size_changed:           page.on(:size_changed) { page_size_changed },
      crop_changed:           page.on(:crop_changed) { emit(:changed) },
      scan_line_changed:      page.on(:scan_line_changed) { emit(:changed) },
      scan_direction_changed: page.on(:scan_direction_changed) { scan_direction_changed },
    }
  end

  # Stops watching the page, which is what upstream's destructor does.
  def disconnect
    @handlers.each { |name, handler| @page.off(name, handler) }
    @handlers = {}
    stop_animation
  end

  def selected? = @selected

  def selected=(value)
    (value ? true : false).then do |wanted|
      unless wanted == @selected
        @selected = wanted
        emit(:changed)
      end
    end
  end

  # Setting one dimension derives the other from the page's aspect, and marks
  # the preview for regeneration.
  def width=(value)
    scaled_height(value).then do |h|
      unless @width == value && @height == h
        @width = value
        @height = h
        @update_image = true
        emit(:size_changed)
        emit(:changed)
      end
    end
  end

  def height=(value)
    scaled_width(value).then do |w|
      unless @width == w && @height == value
        @width = w
        @height = value
        @update_image = true
        emit(:size_changed)
        emit(:changed)
      end
    end
  end

  def preview_width = @width - ((BORDER_WIDTH + RULER_WIDTH) * 2)

  def preview_height = @height - ((BORDER_WIDTH + RULER_WIDTH) * 2)

  # Upstream's button_press: remember where the drag started and what the crop
  # looked like then, so motion can work in deltas.
  def button_press(x, y)
    crop_location_at(x, y).then do |location|
      unless location == CropLocation::NONE
        @crop_location = location
        @selected_crop_px = x
        @selected_crop_py = y
        @selected_crop_x = @page.crop_x
        @selected_crop_y = @page.crop_y
        @selected_crop_w = @page.crop_width
        @selected_crop_h = @page.crop_height
      end
    end
  end

  def button_release(_x, _y)
    @crop_location = CropLocation::NONE
    emit(:changed)
  end

  # Upstream's motion: outside a drag it only picks the cursor; inside one it
  # moves or reshapes the crop, clamped to the page and a minimum size.
  def motion(x, y)
    crop_location_at(x, y).then do |location|
      if @crop_location == CropLocation::NONE
        @cursor = CURSORS.fetch(location, CURSORS[CropLocation::NONE])
      else
        drag_crop(x, y)
      end
    end
  end

  # Paints the page, its rulers, the scan line and the crop into the context.
  def render(context)
    update_animation
    update_preview

    context.save
    context.set_line_width(1)
    context.translate(@x_offset, @y_offset)
    context.translate(BORDER_WIDTH + RULER_WIDTH, BORDER_WIDTH + RULER_WIDTH)

    draw_image(context)
    draw_border(context)
    draw_rulers(context)
    draw_scan_line(context)
    draw_crop(context)
    context.restore
  end

  private

    def scaled_height(value) = (value.to_f * @page.height / [@page.width, 1].max).to_i

    def scaled_width(value) = (value.to_f * @page.width / [@page.height, 1].max).to_i

    def page_pixels_changed
      @update_image = true
      emit(:changed)
    end

    def page_size_changed
      @update_image = true
      emit(:size_changed)
      emit(:changed)
    end

    def scan_direction_changed
      @update_image = true
      @image = nil
      emit(:size_changed)
      emit(:changed)
    end

    def update_preview
      @update_image.then do |stale|
        if stale
          @image = scaled_preview
          @update_image = false
        end
      end
    end

    def scaled_preview
      [preview_width, 1].max.then do |target_width|
        [preview_height, 1].max.then do |target_height|
          @page.get_image(false).scale_simple(target_width, target_height, :bilinear)
        end
      end
    end

    def draw_image(context)
      @image.then do |image|
        unless image.nil?
          context.set_source_pixbuf(image, 0, 0)
          context.paint
        end
      end
    end

    def draw_border(context)
      context.set_source_rgb(@ruler_color.red, @ruler_color.green, @ruler_color.blue)
      context.set_line_width(BORDER_WIDTH)
      context.rectangle(
        0,
        0.0,
        preview_width,
        preview_height,
      )
      context.stroke
    end

    def draw_rulers(context)
      context.set_line_width(1)
      draw_horizontal_ruler(context)
      draw_vertical_ruler(context)
    end

    # A tick every fifth of an inch, and a long tick every inch.
    def ruler_ticks(extent)
      [@page.dpi / 5, 1].max.then do |step|
        (0..extent).step(step).each_with_index.map { |tick, index| [tick, (index % 5).zero?] }
      end
    end

    def draw_horizontal_ruler(context)
      height = preview_height
      ruler_ticks(@page.width).each do |(tick, long)|
        (page_to_screen_x(tick) + 0.5).then do |line|
          if long
            context.move_to(line, 0)
            context.line_to(line, -RULER_WIDTH)
            context.move_to(line, height)
            context.line_to(line, height + RULER_WIDTH)
          else
            context.move_to(line, -2)
            context.line_to(line, -5)
            context.move_to(line, height + 2)
            context.line_to(line, height + 5)
          end
        end
      end
      context.stroke
    end

    def draw_vertical_ruler(context)
      width = preview_width
      ruler_ticks(@page.height).each do |(tick, long)|
        (page_to_screen_y(tick) + 0.5).then do |line|
          if long
            context.move_to(0, line)
            context.line_to(-RULER_WIDTH, line)
            context.move_to(width, line)
            context.line_to(width + RULER_WIDTH, line)
          else
            context.move_to(-2, line)
            context.line_to(-5, line)
            context.move_to(width + 2, line)
            context.line_to(width + 5, line)
          end
        end
      end
      context.stroke
    end

    def draw_scan_line(context)
      (@page.scanning? && @page.scan_line.positive?).then do |scanning|
        if scanning
          scan_line_points.then do |(x1, y1, x2, y2)|
            context.move_to(x1, y1)
            context.line_to(x2, y2)
            context.set_source_rgb(1.0, 0.0, 0.0)
            context.stroke
          end
        end
      end
    end

    def scan_line_points
      width = preview_width
      height = preview_height
      case @page.scan_direction
      when ScanDirection::TOP_TO_BOTTOM
        page_to_screen_y(@page.scan_line).then { |s| [0, s + 0.5, width, s + 0.5] }
      when ScanDirection::BOTTOM_TO_TOP
        page_to_screen_y(@page.scan_line).then { |s| [0, height - s + 0.5, width, height - s + 0.5] }
      when ScanDirection::LEFT_TO_RIGHT
        page_to_screen_x(@page.scan_line).then { |s| [s + 0.5, 0, s + 0.5, height] }
      else
        page_to_screen_x(@page.scan_line).then { |s| [width - s + 0.5, 0, width - s + 0.5, height] }
      end
    end

    def draw_crop(context)
      @page.has_crop?.then do |has_crop|
        if has_crop
          crop_screen_rectangle.then { |rect| paint_crop(context, rect) }
        end
      end
    end

    def crop_screen_rectangle
      [
        page_to_screen_x(@page.crop_x),
        page_to_screen_y(@page.crop_y),
        page_to_screen_x(@page.crop_width),
        page_to_screen_y(@page.crop_height),
      ]
    end

    def paint_crop(context, rect)
      shade_outside_crop(context, rect)
      draw_crop_edges(context, rect)
    end

    def shade_outside_crop(context, (x, y, width, height))
      context.rectangle(
        0,
        0,
        preview_width,
        preview_height,
      )
      context.new_sub_path
      context.rectangle(
        x,
        y,
        width,
        height,
      )
      context.set_fill_rule(Cairo::FILL_RULE_EVEN_ODD)
      context.set_source_rgba(
        0.25,
        0.25,
        0.25,
        0.2,
      )
      context.fill
    end

    def draw_crop_edges(context, (x, y, width, height))
      preview_width.then do |w|
        preview_height.then do |h|
          context.set_source_rgb(1.0, 1.0, 1.0)
          context.move_to(-BORDER_WIDTH, y - 1.5)
          context.line_to(BORDER_WIDTH + w, y - 1.5)
          context.move_to(-BORDER_WIDTH, y + height + 1.5)
          context.line_to(BORDER_WIDTH + w, y + height + 1.5)
          context.stroke

          context.move_to(x - 1.5, -BORDER_WIDTH)
          context.line_to(x - 1.5, BORDER_WIDTH + h)
          context.move_to(x + width + 1.5, -BORDER_WIDTH)
          context.line_to(x + width + 1.5, BORDER_WIDTH + h)
          context.stroke

          context.rectangle(
            x - 0.5,
            y - 0.5,
            width + 1,
            height + 1,
          )
          context.set_source_rgb(0.0, 0.0, 0.0)
          context.stroke
        end
      end
    end

    def page_to_screen_x(x) = ((x.to_f * preview_width / [@page.width, 1].max) + 0.5).to_i

    def page_to_screen_y(y) = ((y.to_f * preview_height / [@page.height, 1].max) + 0.5).to_i

    def screen_to_page_x(x) = ((x.to_f * @page.width / [preview_width, 1].max) + 0.5).to_i

    def screen_to_page_y(y) = ((y.to_f * @page.height / [preview_height, 1].max) + 0.5).to_i

    # Upstream's get_crop_location: which handle, if any, is under the point.
    def crop_location_at(x, y)
      if @page.has_crop?
        crop_handle_at(x, y)
      else
        CropLocation::NONE
      end
    end

    def crop_handle_at(x, y)
      offset = BORDER_WIDTH + RULER_WIDTH
      dx = page_to_screen_x(@page.crop_x) + offset
      dy = page_to_screen_y(@page.crop_y) + offset
      dw = page_to_screen_x(@page.crop_width) + offset
      dh = page_to_screen_y(@page.crop_height) + offset
      ix = x - dx
      iy = y - dy

      if ix.negative? || ix > dw || iy.negative? || iy > dh
        CropLocation::NONE
      elsif !@page.crop_name.nil?
        CropLocation::MIDDLE
      else
        edge_location(
          ix,
          iy,
          dw,
          dh,
        )
      end
    end

    def edge_location(ix, iy, dw, dh)
      border = [CROP_BORDER, dw / 3, dh / 3].min
      near_left = ix < border
      near_right = ix > dw - border
      near_top = iy < border
      near_bottom = iy > dh - border

      corner_location(
        near_left,
        near_right,
        near_top,
        near_bottom,
      ) ||
        side_location(
          near_left,
          near_right,
          near_top,
          near_bottom,
        ) ||
        CropLocation::MIDDLE
    end

    def corner_location(near_left, near_right, near_top, near_bottom)
      if near_left && near_top
        CropLocation::TOP_LEFT
      elsif near_right && near_top
        CropLocation::TOP_RIGHT
      elsif near_left && near_bottom
        CropLocation::BOTTOM_LEFT
      elsif near_right && near_bottom
        CropLocation::BOTTOM_RIGHT
      end
    end

    def side_location(near_left, near_right, near_top, near_bottom)
      if near_left
        CropLocation::LEFT
      elsif near_right
        CropLocation::RIGHT
      elsif near_top
        CropLocation::TOP
      elsif near_bottom
        CropLocation::BOTTOM
      end
    end

    # The body of upstream's motion while a handle is held: work out the
    # clamped delta, apply it to the remembered crop, and push the result back
    # onto the page.
    def drag_crop(x, y)
      clamped_delta(x, y).then do |(dx, dy)|
        moved_crop(dx, dy).then do |(new_x, new_y, new_w, new_h)|
          @page.move_crop(new_x, new_y)
          unless new_w == @page.crop_width && new_h == @page.crop_height
            @page.set_custom_crop(new_w, new_h)
          end
        end
      end
    end

    def clamped_delta(x, y)
      dx = screen_to_page_x(x - @selected_crop_px.to_i)
      dy = screen_to_page_y(y - @selected_crop_py.to_i)
      min_size = screen_to_page_x(MINIMUM_CROP)

      [clamp_dx(dx, min_size), clamp_dy(dy, min_size)]
    end

    LEFT_HANDLES = [CropLocation::TOP_LEFT, CropLocation::LEFT, CropLocation::BOTTOM_LEFT].freeze
    RIGHT_HANDLES = [CropLocation::TOP_RIGHT, CropLocation::RIGHT, CropLocation::BOTTOM_RIGHT].freeze
    TOP_HANDLES = [CropLocation::TOP_LEFT, CropLocation::TOP, CropLocation::TOP_RIGHT].freeze
    BOTTOM_HANDLES = [CropLocation::BOTTOM_LEFT, CropLocation::BOTTOM, CropLocation::BOTTOM_RIGHT].freeze

    def clamp_dx(dx, min_size)
      dx.then do |delta|
        if LEFT_HANDLES.include?(@crop_location)
          [[delta, @selected_crop_w - min_size].min, -@selected_crop_x].max
        elsif RIGHT_HANDLES.include?(@crop_location)
          [[delta, min_size - @selected_crop_w].max, @page.width - @selected_crop_x - @selected_crop_w].min
        elsif @crop_location == CropLocation::MIDDLE
          [[delta, @page.width - @selected_crop_x - @selected_crop_w].min, -@selected_crop_x].max
        else
          delta
        end
      end
    end

    def clamp_dy(dy, min_size)
      dy.then do |delta|
        if TOP_HANDLES.include?(@crop_location)
          [[delta, @selected_crop_h - min_size].min, -@selected_crop_y].max
        elsif BOTTOM_HANDLES.include?(@crop_location)
          [[delta, min_size - @selected_crop_h].max, @page.height - @selected_crop_y - @selected_crop_h].min
        elsif @crop_location == CropLocation::MIDDLE
          [[delta, @page.height - @selected_crop_y - @selected_crop_h].min, -@selected_crop_y].max
        else
          delta
        end
      end
    end

    def moved_crop(dx, dy)
      new_x = @selected_crop_x
      new_y = @selected_crop_y
      new_w = @selected_crop_w
      new_h = @selected_crop_h

      if @crop_location == CropLocation::MIDDLE
        new_x += dx
        new_y += dy
      end
      if LEFT_HANDLES.include?(@crop_location)
        new_x += dx
        new_w -= dx
      end
      if TOP_HANDLES.include?(@crop_location)
        new_y += dy
        new_h -= dy
      end
      if RIGHT_HANDLES.include?(@crop_location)
        new_w += dx
      end
      if BOTTOM_HANDLES.include?(@crop_location)
        new_h += dy
      end

      [new_x, new_y, new_w, new_h]
    end

    # The barber-pole animation upstream runs while a page is being scanned
    # but has no data yet.
    def update_animation
      (@page.scanning? && !@page.has_data?).then do |animate|
        if animate && @animate_timeout.nil?
          start_animation
        elsif !animate && !@animate_timeout.nil?
          stop_animation
        end
      end
    end

    def start_animation
      @animate_segment = 0
      @animate_timeout = GLib::Timeout.add(ANIMATE_INTERVAL) do
        @animate_segment = (@animate_segment + 1) % ANIMATE_SEGMENTS
        emit(:changed)
        true
      end
    end

    def stop_animation
      unless @animate_timeout.nil?
        GLib::Source.remove(@animate_timeout)
      end
      @animate_timeout = nil
    end
end
