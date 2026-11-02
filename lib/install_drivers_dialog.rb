# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

# InstallDriversDialog tells the user where the driver for the scanner they
# have plugged in can be found.
#
# Ported from install_drivers in upstream's src/app-window.vala: the same
# per-backend messages and instructions, and the same closing line.
#
# Upstream can also install a package itself through PackageKit when it was
# built with it; there is no PackageKit binding in ruby-gnome, so the dialog
# names the package to install the way upstream's non-PackageKit build does.
class InstallDriversDialog < Adwaita::Dialog
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
    brother: ['You appear to have a Brother scanner.',
              # Instructions on how to install Brother scanner drivers
              'Drivers for this are available on the ' \
              '<a href="http://support.brother.com">Brother website</a>.'
],
    # Message to indicate a Canon Pixma scanner has been detected
    canon:   ['You appear to have a Canon scanner, which is supported by the ' \
            '<a href="http://www.sane-project.org/man/sane-pixma.5.html">Pixma SANE backend</a>.',
            # Instructions on how to resolve an issue with SANE scanner drivers
            'Please check if your <a href="http://www.sane-project.org/sane-supported-devices.html">scanner is ' \
            'supported by SANE</a>, otherwise report the issue to the ' \
            '<a href="https://alioth-lists.debian.net/cgi-bin/mailman/listinfo/sane-devel">SANE mailing list</a>.'
],
    # Message to indicate a Samsung scanner has been detected
    samsung: ['You appear to have a Samsung scanner.',
              # Because HP acquired Samsung's global printing business in 2017, the support is on HP's site
              'Drivers for this are available on the <a href="https://support.hp.com">HP website</a> ' \
              '(HP acquired Samsung’s printing business).'
],
    # Message to indicate an HP scanner has been detected
    hpaio:   ['You appear to have an HP scanner.', nil],
    # smfp devices are rebranded Samsung models and need drivers that are not in the hpaio package
    smfp:    ['You appear to have an HP scanner.',
           'Drivers for this are available on the <a href="https://support.hp.com">HP website</a>.'
],
    # Message to indicate an Epson scanner has been detected
    epson:   ['You appear to have an Epson scanner.',
            # Instructions on how to install Epson scanner drivers
            'Drivers for this are available on the <a href="http://support.epson.com">Epson website</a>.'
],
    # Message to indicate a Lexmark scanner has been detected
    lexmark: ['You appear to have an Lexmark scanner.',
              # Instructions on how to install Lexmark scanner drivers
              'Drivers for this are available on the <a href="http://support.lexmark.com">Lexmark website</a>.'
],
  }.freeze

  PACKAGES = { hpaio: ['libsane-hpaio'] }.freeze

  def initialize(missing_driver)
    super()
    @driver = DRIVERS[missing_driver.to_s]
    # Title of dialog giving instructions on how to install drivers
    self.title = 'Install drivers'
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
          box.append(instructions_label)
          box.append(restart_label)
        end
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

  def instructions_label
    @instructions_label ||= label_for(instructions)
  end

  def restart_label
    @restart_label ||= label_for(
      # Message in the driver install dialog
      'Once installed you will need to restart this app.',
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

  private

    def package_instructions
      PACKAGES.fetch(@driver, []).then do |packages|
        if packages.empty?
          ''
        else
          # Label shown to prompt the user to install packages
          format(
            packages.length == 1 ? 'You need to install the %s package.' : 'You need to install the %s packages.',
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
