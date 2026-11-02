# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative '../app_window'
require_relative '../resources'
require_relative '../scan_options'
require_relative '../settings'

module SimpleScan
  # Application is the process: it registers the application, builds the
  # window, and connects the window's scan signals to the backend.
  #
  # Ported from the application glue at the top of upstream's
  # src/simple-scan.vala, which builds an AppWindow, builds a Scanner, and
  # wires one to the other.
  #
  # There is no Scanner in this port yet — SANE has no ruby-gnome binding, so
  # driving it needs an FFI layer that is not written. Until it is, the
  # backend reports no devices, which is a state upstream's window already
  # knows how to show: "No Scanners Detected", with the refresh button live.
  # Nothing here pretends a scan happened.
  class Application
    APP_ID = 'org.rubygtkproject.SimpleScan'

    def initialize(app_id: APP_ID, flags: :default_flags, present: true)
      @app_id = app_id
      @flags = flags
      @present = present
      @settings = Settings.new
    end

    def build
      app.tap do |a|
        a.signal_connect('activate') do
          # The three action icons upstream installs into the hicolor theme
          # ship in data/icons; the theme only finds them once the display
          # exists, which it does by the time activate runs.
          Resources.install_icon_search_path

          app_window.build

          app_window.on(:redetect) { detect_devices }

          if @present
            app_window.start
          end

          detect_devices
        end
      end
    end

    def run(argv = []) = app.run(argv)

    # Adwaita::Application is unreliable in these bindings, so the application
    # object is a Gtk::Application and only the window is Adwaita.
    def app = @app ||= Gtk::Application.new(@app_id, @flags)

    def app_window = @app_window ||= AppWindow.new(app, settings: @settings)

    private

    # Upstream hands the window the device list the Scanner found. With no
    # scanner backend the list is empty, which the window shows as "No
    # Scanners Detected" — and which leaves the Scan button insensitive, so
    # the window's start_scan signal is never raised.
      def detect_devices
        app_window.set_scan_devices([])
      end
  end
end
