# frozen_string_literal: true

require 'adwaita'
require 'gtk4'
require 'fileutils'
require 'tmpdir'

require_relative 'about_dialog'
require_relative 'alerts'
require_relative 'authorize_dialog'
require_relative 'autosave_manager'
require_relative 'book'
require_relative 'book_view'
require_relative 'cancellable_progress_bar'
require_relative 'document_action_bar'
require_relative 'install_drivers_dialog'
require_relative 'page'
require_relative 'page_menu'
require_relative 'preferences_dialog'
require_relative 'print_operation'
require_relative 'reorder_pages_dialog'
require_relative 'save_dialog'
require_relative 'scan_options'
require_relative 'scan_options_popover'
require_relative 'scanner_status_page'
require_relative 'screensaver'
require_relative 'settings'
require_relative 'shortcuts_dialog'
require_relative 'simple/scan/rb/version'
require_relative 'translations'

# AppWindow is the main window: the header bar with the Scan and Save buttons,
# the status page shown before there is a document, the book view and the
# action bar under it, and every action and dialog reachable from them.
#
# Ported from upstream's src/app-window.vala and data/ui/app-window.ui.
#
# Upstream is itself a Hdy.ApplicationWindow subclass built from a GtkBuilder
# template. Here the window is composed rather than subclassed, which is the
# shape the rest of this port uses, and the template becomes memoized widget
# methods assembled in build. Everything the template held is covered by one
# of the classes this file requires.
#
# The scanner is not driven from here in either version: upstream emits
# start_scan, stop_scan and redetect and lets src/simple-scan.vala connect
# them to the Scanner, and so does this.
class AppWindow
  include Translations
  extend Translations

  include Signals

  # The app-scoped actions and their accelerators, from the action_entries
  # array and the set_accels_for_action calls in upstream's load.
  ACTIONS = {
    'new_document' => ['<Control>n'],
    'scan_single'  => ['<Control>1'],
    'scan_adf'     => ['<Control>f'],
    'scan_batch'   => ['<Control>m'],
    'scan_stop'    => ['Escape'],
    'rotate_left'  => ['bracketleft'],
    'rotate_right' => ['bracketright'],
    'move_left'    => ['less'],
    'move_right'   => ['greater'],
    'copy_page'    => ['<Control>c'],
    'delete_page'  => ['Delete'],
    'reorder'      => [],
    'save'         => ['<Control>s'],
    'email'        => ['<Control>e'],
    'print'        => ['<Control>p'],
    'preferences'  => [],
    'help'         => ['F1'],
    'shortcuts'    => ['<Control>question'],
    'about'        => [],
    'quit'         => ['<Control>q'],
  }.freeze

  HELP_URI = 'help:simple-scan'

  attr_reader :book, :settings

  def initialize(app, settings: nil, autosave_manager: nil)
    @app = app
    @settings = settings || Settings.new
    @autosave_manager = autosave_manager || AutosaveManager.new
    @screensaver = Screensaver.new
    @book = Book.new
    @book_needs_saving = false
    @book_path = nil
    @scanning = false
    @document_hint = 'photo'
    @scan_type = @settings.scan_type
  end

  def build
    tap do
      window.tap do |win|
        win.content = toolbar_view

        toolbar_view.tap do |view|
          view.add_top_bar(header_bar)
          view.content = stack

          header_bar.tap do |bar|
            bar.pack_start(scan_box)
            bar.pack_start(scan_hint_button)
            bar.pack_end(menu_button)
            bar.pack_end(save_button)
            bar.title_widget = window_title

            scan_box.tap do |box|
              box.append(scan_button)
              box.append(scan_options_button)
              box.append(stop_button)

              scan_button.signal_connect('clicked') { scan_clicked }
              stop_button.signal_connect('clicked') { stop_clicked }
            end

            scan_options_button.popover = scan_options_popover.build

            # Upstream points both the scan-options button and the
            # document-type button at the same popover. A GTK4 popover has one
            # parent, so the popover belongs to the options button and the
            # type button raises it there.
            scan_hint_button.signal_connect('clicked') { scan_options_button.popup }

            save_button.signal_connect('clicked') { save_document }
          end

          stack.tap do |pages|
            pages.add_named(status_page.build, 'startup')
            pages.add_named(document_box, 'document')

            status_page.tap do |page|
              page.on(:status_changed) { |can_scan| scan_button.sensitive = can_scan }
              page.on(:redetect) { emit(:redetect) }
              page.on(:device_selected) { |name| @settings.set_string('selected-device', name) }
              page.on(:activate_link) do |uri|
                if uri == 'install-firmware'
                  install_drivers
                end
              end
            end

            document_box.tap do |box|
              box.append(book_view.build)
              box.append(action_bar.build)
            end
          end

          scan_options_popover.tap do |popover|
            popover.on(:scan_type_changed) { |type| scan_type_changed(type) }
            popover.on(:document_hint_changed) { |hint| document_hint_changed(hint) }
            popover.on(:preferences) { show_preferences }
          end

          action_bar.tap do |bar|
            bar.on(:new_document) { new_document }
            bar.on(:rotate_left) { rotate_left }
            bar.on(:rotate_right) { rotate_right }
            bar.on(:crop_toggled) { |active| set_crop(active ? 'custom' : nil) }
            bar.on(:delete_page) { delete_page }
          end

          book_view.tap do |view|
            view.on(:page_selected) { |page| page_selected(page) }
            view.on(:show_page) { |page| show_page(page) }
            view.on(:show_menu) { |x, y| page_menu.popup_at(view.drawing_area, x, y) }
          end

          window.signal_connect('close-request') do
            quit
            true
          end

          window.signal_connect('notify::default-width') { remember_size }
          window.signal_connect('notify::default-height') { remember_size }
          window.signal_connect('notify::maximized') { remember_window_state }
          window.signal_connect('notify::fullscreen') { remember_window_state }
        end
      end

      page_menu.build
      install_actions
      watch_book
      restore_state
      clear_document
    end
  end

  # Upstream's start: show the window, then offer to restore an autosave.
  def start
    window.present
    @autosave_manager.book = @book

    if @autosave_manager.exists?
      Alerts.confirm_load_autosave(window) { |load| load_autosave(load) }
    else
      adopt_loaded_book
    end
  end

  # Memoized widget methods

  def window
    @window ||= Adwaita::ApplicationWindow.new(@app).tap do |win|
      # Title of the scan window
      win.title = _('Document Scanner')
      win.set_default_size(@settings.window_width, @settings.window_height)
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def window_title
    @window_title ||= Adwaita::WindowTitle.new(_('Document Scanner'), '')
  end

  def scan_box
    @scan_box ||= Gtk::Box.new(:horizontal, 0).tap { |box| box.add_css_class('linked') }
  end

  def scan_button
    @scan_button ||= Gtk::Button.new.tap do |button|
      button.child = scan_button_content
      # Tooltip for the scan toolbar button
      button.tooltip_text = _('Scan a single page from the scanner')
    end
  end

  def scan_button_content
    @scan_button_content ||= Adwaita::ButtonContent.new.tap do |content|
      content.icon_name = 'scanner-symbolic'
      content.label = _('_Scan')
      content.use_underline = true
    end
  end

  def scan_options_button
    @scan_options_button ||= Gtk::MenuButton.new.tap do |button|
      # Tooltip for the scan options button
      button.tooltip_text = _('Choose what to scan')
    end
  end

  def stop_button
    @stop_button ||= Gtk::Button.new.tap do |button|
      button.child = stop_button_box
      # Tooltip for the stop button
      button.tooltip_text = _('Stop the current scan')
      button.visible = false
    end
  end

  def stop_button_box
    @stop_button_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
      box.append(stop_button_spinner)
      box.append(Gtk::Label.new(_('S_top')).tap { |label| label.use_underline = true })
    end
  end

  def stop_button_spinner = @stop_button_spinner ||= Gtk::Spinner.new.tap { |spinner| spinner.spinning = true }

  def scan_hint_button
    @scan_hint_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'image-x-generic-symbolic'
      # Tooltip for the document type button
      button.tooltip_text = _('Choose the type of document being scanned')
    end
  end

  def save_button
    @save_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'document-save-symbolic'
      # Tooltip for the save toolbar button
      button.tooltip_text = _('Save document to a file')
      button.sensitive = false
    end
  end

  def menu_button
    @menu_button ||= Gtk::MenuButton.new.tap do |button|
      button.icon_name = 'open-menu-symbolic'
      button.menu_model = gear_menu
      # Tooltip for the main menu button
      button.tooltip_text = _('Menu')
    end
  end

  # The gear menu, which upstream builds in code rather than in the UI file.
  def gear_menu
    @gear_menu ||= Gio::Menu.new.tap do |menu|
      menu.append_section(nil, document_menu_section)
      menu.append_section(nil, application_menu_section)
    end
  end

  def document_menu_section
    @document_menu_section ||= Gio::Menu.new.tap do |section|
      section.append(_('_Email'), 'app.email')
      section.append(_('Pri_nt'), 'app.print')
      section.append(p_('menu', '_Reorder Pages'), 'app.reorder')
    end
  end

  def application_menu_section
    @application_menu_section ||= Gio::Menu.new.tap do |section|
      section.append(_('_Preferences'), 'app.preferences')
      section.append(_('_Keyboard Shortcuts'), 'app.shortcuts')
      section.append(_('_Help'), 'app.help')
      section.append(_('_About Document Scanner'), 'app.about')
    end
  end

  def stack
    @stack ||= Gtk::Stack.new.tap do |pages|
      pages.vexpand = true
    end
  end

  def status_page = @status_page ||= ScannerStatusPage.new

  def document_box
    @document_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.vexpand = true
    end
  end

  def book_view = @book_view ||= BookView.new(@book)

  def action_bar = @action_bar ||= DocumentActionBar.new

  def page_menu = @page_menu ||= PageMenu.new

  def preferences_dialog = @preferences_dialog ||= PreferencesDialog.new(@settings).build

  def scan_options_popover = @scan_options_popover ||= ScanOptionsPopover.new

  # Public API the scanner service drives, as upstream's does

  def selected_page = book_view.selected_page

  def selected_page=(page)
    book_view.selected_page = page
  end

  def scanning? = @scanning

  # Upstream's scanning property setter: a scan in progress swaps the Scan
  # button for Stop and makes the document visible.
  def scanning=(value)
    if value
      @scanning = true
    else
      @scanning = false
    end
    stack.visible_child_name = 'document'
    action_bar.scanning = @scanning
    scan_button.visible = !@scanning
    stop_button.visible = @scanning

    if @scanning
      @screensaver.inhibit(_('Document Scanner'), _('Scanning'))
    else
      @screensaver.uninhibit
    end
  end

  def set_scan_devices(devices, missing_driver: nil)
    status_page.set_scan_devices(
      devices,
      missing_driver:    missing_driver,
      remembered_device: @settings.get_string('selected-device'),
    )
  end

  def selected_device = status_page.selected_device

  def selected_device=(name)
    status_page.selected_device = name
  end

  def brightness = preferences_dialog.brightness

  def brightness=(value)
    preferences_dialog.brightness = value
  end

  def contrast = preferences_dialog.contrast

  def contrast=(value)
    preferences_dialog.contrast = value
  end

  def page_delay = preferences_dialog.page_delay

  def page_delay=(value)
    preferences_dialog.page_delay = value
  end

  # Upstream's show_error_dialog, which the scanner calls on failure.
  def show_error_dialog(title, text)
    Alerts.error(window, title, text)
  end

  # Upstream's authorize, which the scanner calls for a network device. The
  # credentials go to the block, because GTK4 cannot run a dialog modally.
  def authorize(resource, &on_credentials)
    # Label in authorization dialog. “%s” is replaced with the name of the resource requesting authorization
    format(_('Username and password required to access “%s”'), resource).then do |description|
      AuthorizeDialog.new(description, &on_credentials).build.present(window)
    end
  end

  private

    def install_actions
      ACTIONS.each do |name, accels|
        @app.add_action(Gio::SimpleAction.new(name).tap { |action| action.signal_connect('activate') { activate(name) } })
        unless accels.empty?
          @app.set_accels_for_action("app.#{name}", accels)
        end
      end

      window.add_action(crop_action)
      window.add_action(rotate_crop_action)
    end

    # The crop radio group in the page menu, as one stateful action whose
    # state is the crop name.
    def crop_action
      @crop_action ||= Gio::SimpleAction.new('crop', GLib::VariantType.new('s'), GLib::Variant.new('none')).tap do |action|
        # The activate signal hands the target over already unwrapped, as a
        # Ruby String, so the new state has to be wrapped back up.
        action.signal_connect('activate') do |_action, parameter|
          parameter.to_s.then do |name|
            action.set_state(GLib::Variant.new(name))
            set_crop(name == 'none' ? nil : name)
          end
        end
      end
    end

    def rotate_crop_action
      @rotate_crop_action ||= Gio::SimpleAction.new('rotate_crop').tap do |action|
        action.signal_connect('activate') { selected_page&.rotate_crop }
      end
    end

    # One dispatch table instead of upstream's twenty one-line callbacks.
    def activate(name)
      case name
      when 'new_document' then new_document
      when 'scan_single' then scan_with_type(ScanType::SINGLE)
      when 'scan_adf' then scan_with_type(ScanType::ADF)
      when 'scan_batch' then scan_with_type(ScanType::BATCH)
      when 'scan_stop' then emit(:stop_scan)
      when 'rotate_left' then rotate_left
      when 'rotate_right' then rotate_right
      when 'move_left' then move_left
      when 'move_right' then move_right
      when 'copy_page' then copy_page
      when 'delete_page' then delete_page
      when 'reorder' then reorder_document
      when 'save' then save_document
      when 'email' then email_document
      when 'print' then print_document
      when 'preferences' then show_preferences
      when 'help' then launch_help
      when 'shortcuts' then show_shortcuts
      when 'about' then show_about
      when 'quit' then quit
      end
    end

    def watch_book
      @book.on(:page_added) { update_page_actions }
      @book.on(:page_removed) { update_page_actions }
      @book.on(:reordered) { update_page_actions }
      @book.on(:changed) { book_changed }
    end

    def book_changed
      save_button.sensitive = true
      @book_needs_saving = true
    end

    # Upstream's update_page_menu, which greys out the move items at the ends
    # of the book.
    def update_page_actions
      selected_page.then do |page|
        if page.nil?
          index = nil
        else
          index = @book.get_page_index(page)
        end
        @app.lookup_action('move_left')&.set_enabled(!index.nil? && index.positive?)
        @app.lookup_action('move_right')&.set_enabled(!index.nil? && index < @book.n_pages - 1)
      end
    end

    # Upstream's page_selected_cb: reflect the page's crop onto the menu's
    # radio group and the action bar's toggle.
    def page_selected(page)
      unless page.nil?
        update_page_actions
        crop_action.set_state(GLib::Variant.new(crop_state_for(page)))
        action_bar.show_crop(page.has_crop?)
      end
    end

    def crop_state_for(page)
      if !page.has_crop?
        'none'
      elsif page.crop_name.nil?
        'custom'
      else
        page.crop_name
      end
    end

    # Upstream's set_crop, including the 80%-of-the-page custom crop it starts
    # a custom crop at.
    def set_crop(crop_name)
      rotate_crop_action.set_enabled(!crop_name.nil?)

      selected_page.then do |page|
        if page.nil?
          warn 'Trying to set crop but no selected page'
        elsif crop_name.nil?
          page.set_no_crop
        elsif crop_name == 'custom'
          start_custom_crop(page)
        else
          page.set_named_crop(crop_name)
        end
      end
    end

    def start_custom_crop(page)
      ((page.width * 0.8) + 0.5).to_i.then do |crop_width|
        ((page.height * 0.8) + 0.5).to_i.then do |crop_height|
          page.set_custom_crop(crop_width, crop_height)
          page.move_crop((page.width - crop_width) / 2, (page.height - crop_height) / 2)
        end
      end
    end

    def rotate_left
      selected_page&.rotate_left
    end

    def rotate_right
      selected_page&.rotate_right
    end

    def move_left
      selected_page.then do |page|
        @book.get_page_index(page).then do |index|
          if !index.nil? && index.positive?
            @book.move_page(page, index - 1)
          end
        end
      end
    end

    def move_right
      selected_page.then do |page|
        @book.get_page_index(page).then do |index|
          if !index.nil? && index < @book.n_pages - 1
            @book.move_page(page, index + 1)
          end
        end
      end
    end

    def copy_page
      selected_page&.copy_to_clipboard(window)
    end

    def delete_page
      @book.delete_page(selected_page)
    end

    # Scanning

    def scan_clicked
      scan_with_type(scan_options_popover.scan_type)
    end

    def stop_clicked
      self.scanning = false
      emit(:stop_scan)
    end

    def scan_with_type(type)
      make_scan_options.tap do |options|
        options.type = type
        status_page.contacting_scanner
        emit(:start_scan, selected_device, options)
      end
    end

    # Upstream's make_scan_options.
    def make_scan_options
      ScanOptions.new.tap do |options|
        if @document_hint == 'text'
          options.scan_mode = ScanMode::GRAY
          options.dpi = preferences_dialog.text_dpi
          options.depth = 2
        else
          options.scan_mode = ScanMode::COLOR
          options.dpi = preferences_dialog.photo_dpi
          options.depth = 8
        end

        preferences_dialog.paper_size.then do |(width, height)|
          options.paper_width = width
          options.paper_height = height
        end
        options.brightness = brightness
        options.contrast = contrast
        options.page_delay = page_delay
        options.side = preferences_dialog.page_side
      end
    end

    def scan_type_changed(type)
      @scan_type = type
      @settings.scan_type = type
      @settings.save_state
      scan_button_content.icon_name = scan_options_popover.scan_type_icon
    end

    def document_hint_changed(hint)
      @document_hint = hint
      @settings.set_string('document-type', hint)
      scan_hint_button.icon_name = scan_options_popover.document_hint_icon
    end

    # Documents

    def clear_document
      @book.clear
      @book_needs_saving = false
      @book_path = nil
      save_button.sensitive = false
      status_page.update_status
      stack.visible_child_name = 'startup'
    end

    def new_document
      # Text in dialog warning when a document is about to be lost
      prompt_to_save(_('Save current document?'), _('_Discard Changes')) do
        if @scanning
          emit(:stop_scan)
        end
        clear_document
      end
    end

    # Upstream's prompt_to_save_async, with the block standing in for what it
    # does after the await.
    def prompt_to_save(title, discard_label, &on_continue)
      if !@book_needs_saving || @book.n_pages.zero?
        on_continue.call
      else
        Alerts.prompt_to_save(window, title, discard_label) { |answer| continue_after_save(answer, &on_continue) }
      end
    end

    def continue_after_save(answer, &on_continue)
      case answer
      when :save then save_document { on_continue.call }
      when :discard then on_continue.call
      end
    end

    def save_document(&on_saved)
      SaveDialog.new(@settings, @book, current_path: @book_path) do |path, mime_type, quality|
        write_document(
          path,
          mime_type,
          quality,
          &on_saved
        )
      end.build.present(window)
    end

    def write_document(path, mime_type, quality, &on_saved)
      Gio::Cancellable.new.then do |cancellable|
        save_progress_bar(cancellable).then do |progress|
          save_button.sensitive = false
          @book.save_async(
            mime_type:   mime_type,
            quality:     quality,
            path:        path,
            on_progress: ->(fraction) { progress.fraction = fraction },
            on_finished: ->(error) { document_written(
              error,
              path,
              progress,
              &on_saved
            ) },
            cancellable: cancellable,
          )
        end
      end
    end

    def save_progress_bar(cancellable)
      # Text on the progress bar while saving
      CancellableProgressBar.new(_('Saving'), cancellable).build.tap { |bar| action_bar.pack_end(bar) }
    end

    def document_written(error, path, progress, &on_saved)
      save_button.sensitive = true

      if error.nil?
        progress.destroy_with_delay(500)
        @book_needs_saving = false
        @book_path = path
        on_saved&.call
      else
        action_bar.remove(progress)
        warn "Error saving file: #{error.message}"
        # Title of error dialog when a save failed
        show_error_dialog(_('Failed to save file'), error.message)
      end
    end

    # Upstream's email_document_async: save to a temporary file and hand it to
    # xdg-email.
    def email_document
      email_target.then do |(mime_type, path)|
        @book.save_async(
          mime_type:   mime_type,
          quality:     @settings.get_int('jpeg-quality'),
          path:        path,
          on_finished: ->(error) { send_email(error, mime_type, path) },
        )
      end
    end

    def email_target
      if @document_hint == 'text'
        ['application/pdf', File.join(Dir.mktmpdir('simple-scan'), 'scan.pdf')]
      else
        ['image/jpeg', File.join(Dir.mktmpdir('simple-scan'), 'scan.jpg')]
      end
    end

    def send_email(error, mime_type, path)
      if error.nil?
        spawn_email(email_attachments(mime_type, path))
      else
        warn "Unable to email document: #{error.message}"
      end
    end

    def email_attachments(mime_type, path)
      if mime_type == 'application/pdf'
        [path]
      else
        @book.n_pages.times.map { |index| make_indexed_file(path, index, @book.n_pages) }
      end
    end

    def spawn_email(attachments)
      ['xdg-email', *attachments.flat_map { |path| ['--attach', path] }].then do |command|
        Process.detach(Process.spawn(*command))
      end
    rescue SystemCallError => e
      warn "Unable to email document: #{e.message}"
    end

    def print_document
      print_operation.run(window)
    end

    def print_operation
      @print_operation ||= PrintOperation.new(@book) { |error| warn "Error printing: #{error.message}" }.tap(&:build)
    end

    def reorder_document
      ReorderPagesDialog.new { |choice| apply_reorder(choice) }.build.present(window)
    end

    def apply_reorder(choice)
      case choice
      when :combine_sides then @book.combine_sides
      when :combine_sides_reverse then @book.combine_sides_reverse
      when :reverse then @book.reverse
      end
    end

    # Upstream's show_page_cb: write the page to a temporary PNG and open it
    # in whatever views images.
    def show_page(page)
      preview_file(page).then do |file|
        unless file.nil?
          Gtk::FileLauncher.new(file).launch(window, nil) do |_source, _result|
            nil
          end
        end
      end
    end

    def preview_file(page)
      File.join(Dir.mktmpdir('simple-scan'), 'scan.png').then do |path|
        page.save_png(path)
        Gio::File.new_for_path(path)
      end
    rescue StandardError, GLib::Error => e
      # Error message displayed when unable to save an image for preview
      show_error_dialog(_('Unable to save image for preview'), e.message)
      nil
    end

    def show_preferences
      preferences_dialog.present(window)
    end

    def show_shortcuts
      ShortcutsDialog.new.build.present(window)
    end

    def show_about
      AboutDialog.new.build.present(window)
    end

    def launch_help
      Gtk::UriLauncher.new(HELP_URI).launch(window, nil) do |source, result|
        source.launch_finish(result)
      rescue GLib::Error => e
        # Error message displayed when unable to launch the help browser
        show_error_dialog(_('Unable to open help file'), e.message)
      end
    end

    def install_drivers
      InstallDriversDialog.new(status_page.missing_driver).build.present(window)
    end

    # Quitting and window state

    def quit
      # Text in dialog warning when a document is about to be lost
      prompt_to_save(_('Save document before quitting?'), _('_Quit without Saving')) do
        if @settings.state_write_pending?
          @settings.save_state(force: true)
        end
        @autosave_manager.cleanup
        window.destroy
      end
    end

    def remember_size
      unless window.maximized? || window.fullscreened?
        @settings.window_width = window.default_width
        @settings.window_height = window.default_height
        @settings.save_state
      end
    end

    def remember_window_state
      @settings.window_maximized = window.maximized?
      @settings.window_fullscreen = window.fullscreened?
      @settings.save_state
    end

    def restore_state
      scan_options_popover.scan_type = @settings.scan_type
      scan_options_popover.document_hint = @settings.get_string('document-type')

      if @settings.window_maximized?
        window.maximize
      end
      if @settings.window_fullscreen?
        window.fullscreen
      end
    end

    def load_autosave(load)
      if load
        @autosave_manager.load
      end
      adopt_loaded_book
    end

    # Upstream's tail of start: a restored book is shown straight away and
    # counts as unsaved.
    def adopt_loaded_book
      if @book.n_pages.zero?
        @book_needs_saving = false
      else
        stack.visible_child_name = 'document'
        book_view.selected_page = @book.get_page(0)
        @book_needs_saving = true
        book_changed
      end
    end
end
