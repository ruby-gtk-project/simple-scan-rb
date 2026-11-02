# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative 'page'
require_relative 'translations'

# ScannerStatusPage is the page the window shows before there is a document:
# it says whether a scanner was found, lets the user pick between several, and
# offers to look again.
#
# Ported from the HdyStatusPage and the device_buttons_box beneath it in
# upstream's data/ui/app-window.ui, together with update_scan_status and
# set_scan_devices in src/app-window.vala.
#
# The device list is a Gtk::DropDown over a Gtk::StringList rather than
# upstream's GtkComboBox over a two-column GtkListStore, which GTK4 dropped.
# The device names sit in a parallel array, so the labels can be re-read from
# a redetect without disturbing the selection.
class ScannerStatusPage < Adwaita::Bin
  include Translations
  extend Translations

  include Signals

  def initialize
    super()
    @devices = []
    @have_devices = false
    @missing_driver = nil
    @setting_devices = false
    @user_selected_device = false
  end

  def build
    tap do |bin|
      bin.child = status_page

      status_page.tap do |page|
        page.child = content_box

        content_box.tap do |box|
          box.append(secondary_label)
          box.append(device_buttons_box)

          secondary_label.signal_connect('activate-link') do |_label, uri|
            emit(:activate_link, uri)
            uri == 'install-firmware'
          end

          device_buttons_box.tap do |buttons|
            buttons.append(device_combo)
            buttons.append(refresh_button)

            device_combo.signal_connect('notify::selected') { device_selected }
            refresh_button.signal_connect('clicked') { redetect }
          end
        end
      end

      update_status
    end
  end

  # Memoized widget methods

  def status_page
    @status_page ||= Adwaita::StatusPage.new.tap do |page|
      page.icon_name = 'scanner-symbolic'
      page.vexpand = true
    end
  end

  def content_box
    @content_box ||= Gtk::Box.new(:vertical, 12).tap do |box|
      box.halign = :center
      box.valign = :center
    end
  end

  def secondary_label
    @secondary_label ||= Gtk::Label.new.tap do |label|
      label.wrap = true
      label.justify = :center
      label.max_width_chars = 50
      label.use_markup = true
    end
  end

  def device_buttons_box
    @device_buttons_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
      box.halign = :center
    end
  end

  def device_combo
    @device_combo ||= Gtk::DropDown.new.tap do |combo|
      combo.model = device_labels
      combo.hexpand = false
    end
  end

  def device_labels = @device_labels ||= Gtk::StringList.new([])

  def refresh_button
    @refresh_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'view-refresh-symbolic'
      # Tooltip for refresh button
      button.tooltip_text = _('Refresh device list')
    end
  end

  # The name of the device the user has selected, or nil when there is none.
  def selected_device
    device_combo.selected.then do |index|
      index == Gtk::INVALID_LIST_POSITION ? nil : @devices.dig(index, 0)
    end
  end

  def selected_device_label
    device_combo.selected.then do |index|
      index == Gtk::INVALID_LIST_POSITION ? nil : @devices.dig(index, 1)
    end
  end

  # Upstream's set_selected_device, which is how a --device argument lands.
  def selected_device=(name)
    @user_selected_device = true
    @devices.index { |(device_name, _label)| device_name == name }.then do |index|
      unless index.nil?
        device_combo.selected = index
      end
    end
  end

  # Upstream's set_scan_devices: replace the list, keeping the user's choice
  # if they made one, and otherwise preferring the remembered device.
  def set_scan_devices(devices, missing_driver: nil, remembered_device: nil)
    @have_devices = true
    @missing_driver = missing_driver
    @setting_devices = true

    have_selection = @user_selected_device && !selected_device.nil?
    replace_devices(devices)

    unless have_selection
      restore_selection(remembered_device)
    end

    @setting_devices = false
    update_status
  end

  # Upstream's redetect_button_clicked_cb.
  def redetect
    @have_devices = false
    update_status
    emit(:redetect)
  end

  # Upstream's "Contacting Scanner…", set when a scan starts.
  def contacting_scanner
    status_page.title = _('Contacting Scanner…')
    device_buttons_box.visible = true
    device_buttons_box.sensitive = false
  end

  # Upstream's update_scan_status, which decides the title, the secondary
  # label and which controls are live from the four states it can be in.
  def update_status
    if !@have_devices
      searching_state
    elsif !selected_device.nil?
      ready_state
    elsif !@missing_driver.nil?
      missing_driver_state
    else
      no_scanners_state
    end

    emit(:status_changed, scan_possible?)
  end

  def scan_possible? = @have_devices && !selected_device.nil?

  def missing_driver = @missing_driver

  private

    def replace_devices(devices)
      devices.map { |device| [device.name, device.label] }.then do |pairs|
        @devices = pairs
        device_labels.splice(0, device_labels.n_items, pairs.map(&:last))
      end
    end

    def restore_selection(remembered_device)
      @devices.index { |(name, _label)| name == remembered_device }.then do |index|
        if @devices.empty?
          nil
        else
          device_combo.selected = index || 0
        end
      end
    end

    def device_selected
      unless @setting_devices
        @user_selected_device = true
        selected_device.then do |name|
          unless name.nil?
            emit(:device_selected, name)
          end
        end
      end
    end

    def searching_state
      # Label shown when searching for scanners
      status_page.title = _('Searching for Scanners…')
      secondary_label.visible = false
      device_buttons_box.visible = false
    end

    def ready_state
      # Label shown when a scanner was detected
      status_page.title = _('Ready to Scan')
      secondary_label.label = selected_device_label.to_s
      secondary_label.visible = false
      device_buttons_box.visible = true
      device_buttons_box.sensitive = true
      device_combo.sensitive = true
    end

    def missing_driver_state
      # Warning displayed when no drivers are installed but a compatible scanner is detected
      status_page.title = _('Additional Software Needed')
      # Instructions to install driver software
      secondary_label.label = _('You need to <a href="install-firmware">install driver software</a> for your scanner.')
      secondary_label.visible = true
      device_buttons_box.visible = false
    end

    def no_scanners_state
      # Warning displayed when no scanners are detected
      status_page.title = _('No Scanners Detected')
      # Hint to the user on why there are no scanners detected
      secondary_label.label = _('Please check your scanner is connected and powered on.')
      secondary_label.visible = true
      device_buttons_box.visible = true
      device_buttons_box.sensitive = true
      # The refresh button stays usable even though there is nothing to choose
      device_combo.sensitive = false
    end
end
