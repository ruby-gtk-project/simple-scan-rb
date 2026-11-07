# frozen_string_literal: true

require 'adwaita'
require 'gtk4'
require 'glib2'
require 'packagekit_glib'

require_relative 'translations'

# InstallDriversDialog tells the user where the driver for the scanner they
# have plugged in can be found.
#
# Ported from install_drivers in upstream's src/app-window.vala: the same
# per-backend messages and instructions, the same closing line, and — for a
# backend with a known package name — the same #if HAVE_PACKAGEKIT branch:
# a Pk.Task resolves the package then installs it, with a spinner/status
# Gtk::Stack standing in for upstream's stack/spinner/status_label trio.
# The install runs on a Ruby Thread because PackageKitGlib::Task only
# exposes the resolve_sync/install_packages_sync pair's blocking D-Bus
# round trip (see the packagekit-glib README); the result is marshalled
# back to the GTK main loop with GLib::Idle.add, the same hand-off upstream
# gets for free from vala's `yield`.
class InstallDriversDialog < Adwaita::Dialog
  include Translations
  extend Translations

  # Message, instructions and packages per SANE backend, from upstream's
  # switch on missing_driver.
  DRIVERS = {
    'brscan'        => :brother,
    'brscan2'       => :brother,
    'brscan3'       => :brother,
    'brscan4'       => :brother,
    'pixma'         => :canon,
    'samsung'       => :samsung,
    'hpaio'         => :hpaio,
    'smfp'          => :smfp,
    'epkowa'        => :epson,
    'lexmark_nscan' => :lexmark,
  }.freeze

  MESSAGES = {
    # Message to indicate a Brother scanner has been detected
    brother: [_('You appear to have a Brother scanner.'),
              # Instructions on how to install Brother scanner drivers
              _(
                'Drivers for this are available on the ' \
                                '<a href="http://support.brother.com">Brother website</a>.',
              )
],
    # Message to indicate a Canon Pixma scanner has been detected
    canon:   [_(
      'You appear to have a Canon scanner, which is supported by the ' \
                    '<a href="http://www.sane-project.org/man/sane-pixma.5.html">Pixma SANE backend</a>.',
    ),
            # Instructions on how to resolve an issue with SANE scanner drivers
            _(
              'Please check if your <a href="http://www.sane-project.org/sane-supported-devices.html">scanner is ' \
                            'supported by SANE</a>, otherwise report the issue to the ' \
                            '<a href="https://alioth-lists.debian.net/cgi-bin/mailman/listinfo/sane-devel">SANE mailing list</a>.',
            )
],
    # Message to indicate a Samsung scanner has been detected
    samsung: [_('You appear to have a Samsung scanner.'),
              # Because HP acquired Samsung's global printing business in 2017, the support is on HP's site
              _(
                'Drivers for this are available on the <a href="https://support.hp.com">HP website</a> ' \
                                '(HP acquired Samsung’s printing business).',
              )
],
    # Message to indicate an HP scanner has been detected
    hpaio:   [_('You appear to have an HP scanner.'), nil],
    # smfp devices are rebranded Samsung models and need drivers that are not in the hpaio package
    smfp:    [_('You appear to have an HP scanner.'),
           _('Drivers for this are available on the <a href="https://support.hp.com">HP website</a>.')
],
    # Message to indicate an Epson scanner has been detected
    epson:   [_('You appear to have an Epson scanner.'),
            # Instructions on how to install Epson scanner drivers
            _('Drivers for this are available on the <a href="http://support.epson.com">Epson website</a>.')
],
    # Message to indicate a Lexmark scanner has been detected
    lexmark: [_('You appear to have an Lexmark scanner.'),
              # Instructions on how to install Lexmark scanner drivers
              _('Drivers for this are available on the <a href="http://support.lexmark.com">Lexmark website</a>.')
],
  }.freeze

  PACKAGES = { hpaio: ['libsane-hpaio'] }.freeze

  def initialize(missing_driver)
    super()
    @driver = DRIVERS[missing_driver.to_s]
    # Title of dialog giving instructions on how to install drivers
    self.title = _('Install drivers')
    self.content_width = 460
  end

  def build
    tap do |dialog|
      dialog.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = content_box

        content_box.tap do |box|
          box.append(message_label)
          box.append(install_row)
          box.append(restart_label)
        end
      end

      if auto_install?
        start_install
      end
    end
  end

  # Memoized widget methods

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def content_box
    @content_box ||= Gtk::Box.new(:vertical, 6).tap do |box|
      box.margin_top = 12
      box.margin_bottom = 12
      box.margin_start = 12
      box.margin_end = 12
    end
  end

  def message_label
    @message_label ||= label_for(message)
  end

  # Mirrors upstream's instructions_box: a status stack (spinner while
  # installing, a ☑/☒ glyph once done) beside the instructions label. The
  # stack stays invisible for a backend with no package to auto-install.
  def install_row
    @install_row ||= Gtk::Box.new(:horizontal, 6).tap do |box|
      box.append(status_stack)
      box.append(instructions_label)
    end
  end

  def status_stack
    @status_stack ||= Gtk::Stack.new.tap do |stack|
      stack.add_named(spinner, 'spinner')
      stack.add_named(status_label, 'status')
      stack.visible_child_name = 'spinner'
      stack.visible = false
    end
  end

  def spinner = @spinner ||= Gtk::Spinner.new

  def status_label = @status_label ||= Gtk::Label.new('')

  def instructions_label
    @instructions_label ||= label_for(instructions)
  end

  def restart_label
    @restart_label ||= label_for(
      # Message in the driver install dialog
      _('Once installed you will need to restart this app.'),
    )
  end

  def message = MESSAGES.dig(@driver, 0).to_s

  # The instructions for this backend, or the package to install when upstream
  # would have installed it through PackageKit.
  def instructions
    MESSAGES.dig(@driver, 1).then do |text|
      text.nil? ? package_instructions : text
    end
  end

  # True once start_install has kicked off a Pk.Task round trip and we are
  # waiting for the main loop to pick up its result.
  def installing? = @installing == true

  # True once that round trip has reported success or failure.
  def install_finished? = @installing == false

  private

    def auto_install? = PACKAGES.fetch(@driver, []).any?

    # Upstream's install_packages: Pk.Task#resolve_async then
    # #install_packages_async on the resolved ids, kicked off from
    # install_drivers when packages_to_install is non-empty.
    def start_install
      @installing = true
      spinner.start
      status_stack.visible = true
      # Label shown while installing drivers
      instructions_label.label = _('Installing drivers…')
      packages = PACKAGES.fetch(@driver, [])
      Thread.new do
        outcome = perform_install(packages)
        GLib::Idle.add do
          apply_install_result(outcome)
          false
        end
      end
    end

    def perform_install(packages)
      task = PackageKitGlib::Task.new
      resolved = task.resolve_sync(PackageKitGlib::FilterEnum::NOT_INSTALLED, packages, nil) { |_progress, _type| }
      if resolved.error_code
        [:failed, resolved.error_code.code]
      else
        install_resolved(task, resolved.package_array.map(&:package_id))
      end
    rescue StandardError => e
      warn "Failed to install drivers: #{e.message}"
      [:error, nil]
    end

    def install_resolved(task, ids)
      if ids.empty?
        [:success, nil]
      else
        installed = task.install_packages_sync(ids, nil) { |_progress, _type| }
        installed.error_code ? [:failed, installed.error_code.code] : [:success, nil]
      end
    end

    def apply_install_result((status, code))
      @installing = false
      spinner.stop
      status_stack.visible_child_name = 'status'
      case status
      when :success
        status_label.label = '☑'
        # Label shown once drivers successfully installed
        instructions_label.label = _('Drivers installed successfully!')
      when :failed
        status_label.label = '☒'
        # Label shown if failed to install drivers
        instructions_label.label = format(_('Failed to install drivers (error code %d).'), code)
      else
        status_label.label = '☒'
        # Label shown if failed to install drivers
        instructions_label.label = _('Failed to install drivers.')
      end
    end

    def package_instructions
      PACKAGES.fetch(@driver, []).then do |packages|
        if packages.empty?
          ''
        else
          # Label shown to prompt the user to install packages
          format(
            n_('You need to install the %s package.', 'You need to install the %s packages.', packages.length),
            packages.join(', '),
          )
        end
      end
    end

    def label_for(text)
      Gtk::Label.new(text).tap do |label|
        label.use_markup = true
        label.wrap = true
        label.xalign = 0
        label.max_width_chars = 50
      end
    end
end
