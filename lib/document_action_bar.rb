# frozen_string_literal: true

require 'gtk4'

require_relative 'page'

# DocumentActionBar is the bar under the document: a New Document button on
# the left, and rotate, crop and delete in the middle.
#
# Ported from the block of src/app-window.vala's load that populates the
# GtkActionBar in code, with the comment explaining that Glade could not do
# it. The widgets and their tooltips are upstream's.
class DocumentActionBar < Gtk::ActionBar
  include Signals

  def initialize
    super()
    @updating = false
  end

  def build
    tap do |bar|
      bar.pack_start(new_document_button)
      bar.set_center_widget(center_box)

      new_document_button.signal_connect('clicked') { emit(:new_document) }

      center_box.tap do |box|
        box.append(rotate_box)
        box.append(crop_button)
        box.append(delete_button)

        rotate_box.tap do |rotate|
          rotate.append(rotate_left_button)
          rotate.append(rotate_right_button)

          rotate_left_button.signal_connect('clicked') { emit(:rotate_left) }
          rotate_right_button.signal_connect('clicked') { emit(:rotate_right) }
        end

        crop_button.signal_connect('toggled') do |button|
          unless @updating
            emit(:crop_toggled, button.active?)
          end
        end

        delete_button.signal_connect('clicked') { emit(:delete_page) }
      end
    end
  end

  # Memoized widget methods

  def new_document_button
    @new_document_button ||= Gtk::Button.new.tap do |button|
      # Label on new document button
      button.label = '_New Document'
      button.use_underline = true
    end
  end

  def center_box = @center_box ||= Gtk::Box.new(:horizontal, 10)

  def rotate_box
    @rotate_box ||= Gtk::Box.new(:horizontal, 0).tap { |box| box.add_css_class('linked') }
  end

  def rotate_left_button
    @rotate_left_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'object-rotate-left-symbolic'
      # Tooltip for rotate left (counter-clockwise) button
      button.tooltip_text = 'Rotate the page to the left (counter-clockwise)'
    end
  end

  def rotate_right_button
    @rotate_right_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'object-rotate-right-symbolic'
      # Tooltip for rotate right (clockwise) button
      button.tooltip_text = 'Rotate the page to the right (clockwise)'
    end
  end

  def crop_button
    @crop_button ||= Gtk::ToggleButton.new.tap do |button|
      button.icon_name = 'crop-symbolic'
      # Tooltip for crop button
      button.tooltip_text = 'Crop the selected page'
    end
  end

  def delete_button
    @delete_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'user-trash-symbolic'
      # Tooltip for delete button
      button.tooltip_text = 'Delete the selected page'
    end
  end

  # Reflects the selected page's crop onto the toggle without the toggle
  # reading back as a user choice, which is what upstream's
  # updating_page_menu flag is for.
  def show_crop(active)
    @updating = true
    crop_button.active = active
    @updating = false
  end

  # Upstream disables delete while a scan is running.
  def scanning=(scanning)
    delete_button.sensitive = !scanning
  end
end
