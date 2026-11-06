# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative '../app_window'
require_relative '../page'
require_relative '../resources'
require_relative '../sane_api'
require_relative '../scan_options'
require_relative '../scanner'
require_relative '../settings'
require_relative '../translations'

module SimpleScan
  # Application is the process: it registers the application, builds the
  # window, builds the Scanner, and wires one to the other.
  #
  # Ported from the application glue in upstream's src/simple-scan.vala —
  # SimpleScan.startup, .activate, .shutdown and the scanner_*_cb family that
  # turns Scanner's signals into pages appended to the book.
  class Application
    include Translations

    APP_ID = 'org.rubygtkproject.SimpleScan'

    def initialize(app_id: APP_ID, flags: :default_flags, present: true)
      @app_id = app_id
      @flags = flags
      @present = present
      @settings = Settings.new
      @scanned_page = nil
    end

    def build
      app.tap do |a|
        a.signal_connect('activate') do
          # The three action icons upstream installs into the hicolor theme
          # ship in data/icons; the theme only finds them once the display
          # exists, which it does by the time activate runs.
          Resources.install_icon_search_path

          app_window.build
          connect_window
          connect_scanner

          if @present
            app_window.start
          end

          scanner.start
        end

        a.signal_connect('shutdown') { scanner.free }
      end
    end

    def run(argv = []) = app.run(argv)

    # Adwaita::Application is unreliable in these bindings, so the application
    # object is a Gtk::Application and only the window is Adwaita.
    def app = @app ||= Gtk::Application.new(@app_id, @flags)

    def app_window = @app_window ||= AppWindow.new(app, settings: @settings)

    def scanner = @scanner ||= Scanner.new

    private

      # Upstream's app.start_scan/stop_scan/redetect connections.
      def connect_window
        app_window.on(:start_scan) { |device, options| scan_cb(device, options) }
        app_window.on(:stop_scan) { scanner.cancel }
        app_window.on(:redetect) { scanner.redetect }
      end

      # Upstream's scanner.*.connect calls in SimpleScan.startup.
      def connect_scanner
        scanner.on(:update_devices) { |devices| update_scan_devices_cb(devices) }
        scanner.on(:request_authorization) { |resource| authorize_cb(resource) }
        scanner.on(:expect_page) { scanner_new_page_cb }
        scanner.on(:got_page_info) { |info| scanner_page_info_cb(info) }
        scanner.on(:got_line) { |line| @scanned_page&.parse_scan_line(line) }
        scanner.on(:page_done) { scanner_page_done_cb }
        scanner.on(:document_done) { scanner_document_done_cb }
        scanner.on(:scan_failed) { |code, message| scanner_failed_cb(code, message) }
        scanner.on(:scanning_changed) { app_window.scanning = scanner.scanning? }
      end

      # Upstream's update_scan_devices_cb, minus the USB vendor/product
      # driver-suggestion table, which needs a GUsb binding this port does
      # not have.
      def update_scan_devices_cb(devices)
        app_window.set_scan_devices(devices)
      end

      def authorize_cb(resource)
        app_window.authorize(resource) { |username, password| scanner.authorize(username, password) }
      end

      # Upstream's append_page: reuse the current page if it is still empty,
      # otherwise start a fresh one with the previous page's geometry and crop.
      def append_page(width: 100, height: 100, dpi: 100)
        page = app_window.book.get_page(-1)
        if page && !page.has_data?
          app_window.selected_page = page
          page.start
          page
        else
          start_new_page(page, width: width, height: height, dpi: dpi)
        end
      end

      def start_new_page(page, width:, height:, dpi:)
        if page
          width = page.width
          height = page.height
          dpi = page.dpi
        end

        new_page = Page.new(width: width, height: height, dpi: dpi, scan_direction: page&.scan_direction || ScanDirection::TOP_TO_BOTTOM)
        app_window.book.append_page(new_page)
        if page&.has_crop?
          if page.crop_name.nil?
            new_page.set_custom_crop(page.crop_width, page.crop_height)
          else
            new_page.set_named_crop(page.crop_name)
          end
          new_page.move_crop(page.crop_x, page.crop_y)
        end
        app_window.selected_page = new_page
        new_page.start

        new_page
      end

      def scanner_new_page_cb
        append_page
      end

      def scanner_page_info_cb(info)
        @scanned_page = append_page
        @scanned_page.set_page_info(info)
      end

      def scanner_page_done_cb
        @scanned_page&.finish
        @scanned_page = nil
      end

      # Upstream's remove_empty_page.
      def remove_empty_page
        page = app_window.book.get_page(app_window.book.n_pages - 1)
        if page && !page.has_data?
          app_window.book.delete_page(page)
        end
      end

      def scanner_document_done_cb
        remove_empty_page
      end

      def scanner_failed_cb(error_code, error_string)
        remove_empty_page
        @scanned_page = nil
        if error_code != SaneApi::STATUS_CANCELLED
          # Title of error dialog when scan failed
          app_window.show_error_dialog(_('Failed to scan'), error_string)
        end
      end

      # Upstream's scan_cb: a fresh page is started immediately so the book
      # view has something to show before the first line arrives.
      def scan_cb(device, options)
        unless scanner.scanning?
          # +1 on each dimension to avoid visual glitches, as upstream notes.
          append_page(width: options.paper_width + 1, height: options.paper_height + 1, dpi: options.dpi + 1)
        end

        scanner.scan(device, options)
      end
  end
end
