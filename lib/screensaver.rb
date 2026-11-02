# frozen_string_literal: true

require 'gtk4'

# Screensaver keeps the session awake while a scan is running.
#
# Ported from upstream's src/screensaver.vala, which declares the
# org.freedesktop.ScreenSaver interface and lets Vala generate a proxy for it.
# There is no interface-generating binding in ruby-gnome, so the two calls go
# through a Gio::DBusProxy by name.
#
# Call arguments are GVariant tuples, and the Ruby bindings cannot build a
# tuple from an Array — GLib::Variant.new(["a", "b"]) yields an array of
# strings, type "as", which D-Bus rejects. Parsing GVariant text is the route
# that works, so the arguments are formatted into that syntax here.
#
# The cookie Inhibit returns has to be handed back to UnInhibit, so it is kept
# here rather than by the caller.
class Screensaver
  BUS_NAME = 'org.freedesktop.ScreenSaver'
  OBJECT_PATH = '/org/freedesktop/ScreenSaver'
  INTERFACE = 'org.freedesktop.ScreenSaver'

  def initialize
    @cookie = nil
  end

  def inhibited? = !@cookie.nil?

  # Returns the cookie on success, and nil when there is no screensaver on the
  # bus to ask — the scan still runs, it just will not hold the session awake.
  def inhibit(application_name, reason)
    if inhibited?
      @cookie
    else
      @cookie = call_inhibit(application_name, reason)
    end
  end

  def uninhibit
    @cookie.then do |cookie|
      unless cookie.nil?
        call_uninhibit(cookie)
        @cookie = nil
      end
    end
  end

  private

    def call_inhibit(application_name, reason)
      proxy.then do |connection|
        if connection.nil?
          nil
        else
          connection.call_sync(
            'Inhibit',
            string_pair(application_name, reason),
            :none,
            -1,
          ).value.first
        end
      end
    rescue GLib::Error => e
      warn "Failed to inhibit the screensaver: #{e.message}"
      nil
    end

    def call_uninhibit(cookie)
      proxy&.call_sync(
        'UnInhibit',
        GLib::Variant.parse("(uint32 #{cookie.to_i},)"),
        :none,
        -1,
      )
    rescue GLib::Error => e
      warn "Failed to uninhibit the screensaver: #{e.message}"
    end

    def string_pair(first, second)
      GLib::Variant.parse("(#{quote(first)}, #{quote(second)})")
    end

    def quote(text) = "'#{text.to_s.gsub('\\', '\\\\\\\\').gsub("'", "\\\\'")}'"

    def proxy
      @proxy ||= Gio::DBusProxy.new_for_bus(
        :session,
        :none,
        nil,
        BUS_NAME,
        OBJECT_PATH,
        INTERFACE,
      )
    rescue GLib::Error => e
      warn "Failed to reach the screensaver: #{e.message}"
      nil
    end
end
