# frozen_string_literal: true

require 'gtk4'

require_relative 'translations'

# PageMenu is the context menu a right click on a page raises.
#
# Ported from the GtkMenu with id page_menu at the top of upstream's
# data/ui/app-window.ui: rotate, a crop submenu of mutually exclusive paper
# sizes with "Rotate Crop" under them, move left and right, copy and delete.
#
# GTK4 has no GtkMenu, so the same items are a Gio::Menu model shown in a
# Gtk::PopoverMenu. The radio items become one stateful "crop" action whose
# state is the crop name, which is how a menu model expresses a radio group,
# and it also removes the updating_page_menu flag upstream needs to stop a
# programmatic toggle from being read back as a user choice.
class PageMenu
  include Translations
  extend Translations

  # The crop submenu, in upstream's order. The value is the crop name the
  # window's crop action takes; "none" and "custom" are upstream's two special
  # cases, the rest are paper sizes Page#set_named_crop knows.
  CROPS = [
    # Radio button for no crop
    [_('_None'), 'none'],
    [_('A_4'), 'A4'],
    [_('A_5'), 'A5'],
    [_('A_6'), 'A6'],
    # Radio button for cropping page to US letter size
    [_('_Letter'), 'letter'],
    # Radio button for cropping page to US legal size
    [_('Le_gal'), 'legal'],
    [_('4×6'), '4x6'],
    [_('A_3'), 'A3'],
    # Radio button for cropping to a custom page size
    [_('_Custom'), 'custom'],
  ].freeze

  def build
    popover.tap do |menu|
      menu.menu_model = model
      menu.has_arrow = false
    end
  end

  def popover = @popover ||= Gtk::PopoverMenu.new.tap { |menu| menu.halign = :start }

  def model
    @model ||= Gio::Menu.new.tap do |menu|
      menu.append_section(nil, rotate_section)
      menu.append_submenu(
        # Label for page crop submenu
        _('_Crop'),
        crop_section,
      )
      menu.append_section(nil, move_section)
      menu.append_section(nil, page_section)
    end
  end

  # Pops the menu up at a point in the given widget's coordinates, which is
  # what upstream's popup_at_pointer does with the click event.
  def popup_at(widget, x, y)
    popover.tap do |menu|
      unless menu.parent.equal?(widget)
        menu.unparent
        menu.set_parent(widget)
      end
      menu.pointing_to = Gdk::Rectangle.new(
        x.to_i,
        y.to_i,
        1,
        1,
      )
      menu.popup
    end
  end

  private

    def rotate_section
      Gio::Menu.new.tap do |section|
        # Menu item to rotate page to left (anti-clockwise)
        section.append(_('Rotate _Left'), 'app.rotate_left')
        # Menu item to rotate page to right (clockwise)
        section.append(_('Rotate _Right'), 'app.rotate_right')
      end
    end

    def crop_section
      Gio::Menu.new.tap do |section|
        Gio::Menu.new.tap do |sizes|
          CROPS.each { |(label, name)| sizes.append_item(crop_item(label, name)) }
          section.append_section(nil, sizes)
        end

        Gio::Menu.new.tap do |rotate|
          # Menu item to rotate the crop area
          rotate.append(_('_Rotate Crop'), 'win.rotate_crop')
          section.append_section(nil, rotate)
        end
      end
    end

    def crop_item(label, name)
      Gio::MenuItem.new(label, nil).tap do |item|
        item.set_action_and_target_value('win.crop', GLib::Variant.new(name))
      end
    end

    def move_section
      Gio::Menu.new.tap do |section|
        # Menu item to move the selected page to the left
        section.append(_('Move Left'), 'app.move_left')
        # Menu item to move the selected page to the right
        section.append(_('Move Right'), 'app.move_right')
      end
    end

    def page_section
      Gio::Menu.new.tap do |section|
        section.append('_Copy', 'app.copy_page')
        section.append('_Delete', 'app.delete_page')
      end
    end
end
