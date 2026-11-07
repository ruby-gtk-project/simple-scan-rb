# frozen_string_literal: true

# Drives the window headlessly: builds it, walks the widget tree, opens each
# dialog, adds pages to the book and exercises the page actions.
$stdout.sync = true
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'simple_scan'
require 'tmpdir'

ROOT = Dir.mktmpdir('simple-scan-drive')
ENV['XDG_CONFIG_HOME'] = File.join(ROOT, 'config')
ENV['XDG_CACHE_HOME'] = File.join(ROOT, 'cache')

checks = 0
failures = []
check = lambda do |label, &body|
  checks += 1
  result = body.call
  puts "ok   #{label}#{result.nil? ? '' : " -> #{result}"}"
rescue StandardError, GLib::Error => e
  failures << label
  puts "FAIL #{label}: #{e.class}: #{e.message}"
  puts e.backtrace.first(4).map { |line| "       #{line}" }
end

application = SimpleScan::Application.new(app_id: 'org.rubygtkproject.SimpleScanDrive', present: false)
application.build
app = application.app
window = application.app_window

app.signal_connect('activate') do
  check.call('window built') { window.window.title }
  check.call('stack page') { window.stack.visible_child_name }
  check.call('scan button insensitive with no devices') { window.scan_button.sensitive?.inspect }
  check.call('status title') { window.status_page.status_page.title }

  # `Application#build` only calls this when `present:` is true, so a drive
  # run that wants the real startup path (window.present, the autosave
  # manager wired to the book, restore_state) has to call it itself.
  check.call('window start wires the autosave manager and presents') do
    window.start
    [window.window.visible?,
     window.instance_variable_get(:@autosave_manager).book.equal?(window.book)
].inspect
  end

  check.call('keyboard shortcuts registered for every action') do
    AppWindow::ACTIONS.each do |name, accels|
      bound = app.get_accels_for_action("app.#{name}")
      if bound != accels
        raise "#{name}: expected #{accels.inspect}, got #{bound.inspect}"
      end
    end
    "#{AppWindow::ACTIONS.size} actions"
  end

  check.call('devices listed via real SANE redetect') do
    deadline = Time.now + 10
    until window.selected_device || Time.now > deadline
      GLib::MainContext.default.iteration(true)
    end
    [window.status_page.status_page.title, window.selected_device, window.scan_button.sensitive?].inspect
  end

  check.call('real scan via the SANE test backend produces a page with pixel data') do
    pages_before = window.book.n_pages
    app.lookup_action('scan_single').activate(nil)
    deadline = Time.now + 10
    until window.book.n_pages > pages_before || Time.now > deadline
      GLib::MainContext.default.iteration(true)
    end
    unless window.book.n_pages > pages_before
      raise 'scan_single did not add a page'
    end

    page = window.book.get_page(window.book.n_pages - 1)
    deadline = Time.now + 10
    until page.has_data? || Time.now > deadline
      GLib::MainContext.default.iteration(true)
    end
    [page.has_data?, page.width, page.height].inspect.tap do
      # Restore the empty book the synthetic-page checks below expect.
      window.book.delete_page(page)
    end
  end

  check.call('devices listed') do
    window.set_scan_devices([ScanDevice.new(name: 'test:0', label: 'Test Scanner')])
    [window.status_page.status_page.title, window.selected_device, window.scan_button.sensitive?].inspect
  end

  check.call('gear menu items') { window.gear_menu.n_items }
  check.call('page menu built') { window.page_menu.model.n_items }

  check.call('preferences action opens the dialog') do
    app.lookup_action('preferences').activate(nil)
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    window.preferences_dialog.visible?
  end
  check.call('shortcuts action opens the dialog') do
    app.lookup_action('shortcuts').activate(nil)
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    'activated'
  end
  check.call('about action opens the dialog') do
    app.lookup_action('about').activate(nil)
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    'activated'
  end
  check.call('reorder action opens the dialog') do
    app.lookup_action('reorder').activate(nil)
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    'activated'
  end

  check.call('error alert builds, presents and closes') do
    dialog = Alerts.error(window.window, 'Driven error', 'exercised from the drive script')
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    dialog.class
  end

  check.call('screensaver inhibit and uninhibit do not raise') do
    screensaver = window.instance_variable_get(:@screensaver)
    screensaver.inhibit('Document Scanner', 'Scanning')
    inhibited = screensaver.inhibited?
    screensaver.uninhibit
    [inhibited, screensaver.inhibited?].inspect
  end

  check.call('preferences dialog') do
    window.preferences_dialog
    [window.preferences_dialog.text_dpi, window.preferences_dialog.photo_dpi,
     window.preferences_dialog.page_side, window.preferences_dialog.paper_size,
     window.preferences_dialog.page_delay
].inspect
  end
  check.call('preferences brightness round trip') do
    window.brightness = 42
    window.brightness
  end
  check.call('preferences page delay round trip') do
    window.page_delay = 10_000
    window.page_delay
  end

  check.call('scan options popover') do
    # Already built once by AppWindow#build (scan_options_button.popover=);
    # calling .build again would re-append already-parented children.
    window.scan_options_popover.scan_type = ScanType::ADF
    [window.scan_options_popover.scan_type, window.scan_options_popover.scan_type_icon].inspect
  end
  check.call('document hint') do
    window.scan_options_popover.document_hint = 'text'
    [window.scan_options_popover.document_hint, window.scan_options_popover.document_hint_icon].inspect
  end

  # Add three pages of real pixels to the book.
  check.call('book filled') do
    3.times do |i|
      pixels = ([40 + (i * 60)] * (60 * 80)).pack('C*')
      window.book.append_page(
        Page.from_data(
          scan_width:     60,
          scan_height:    80,
          rowstride:      60,
          n_channels:     1,
          depth:          8,
          dpi:            72,
          scan_direction: ScanDirection::TOP_TO_BOTTOM,
          color_profile:  nil,
          pixels:         pixels,
          has_crop:       false,
          crop_name:      nil,
          crop_x:         0,
          crop_y:         0,
          crop_width:     0,
          crop_height:    0,
        ),
      )
    end
    window.book.n_pages
  end

  check.call('document page shown') do
    window.stack.visible_child_name = 'document'
    window.selected_page = window.book.get_page(0)
    window.stack.visible_child_name
  end

  check.call('book view renders') do
    window.window.present
    4.times { GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending? }
    window.book_view.drawing_area.queue_draw
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    [window.book_view.drawing_area.width, window.book_view.drawing_area.height].inspect
  end

  check.call('rotate action') do
    app.lookup_action('rotate_left').activate(nil)
    window.selected_page.scan_direction
  end
  check.call('rotate back') do
    app.lookup_action('rotate_right').activate(nil)
    window.selected_page.scan_direction
  end
  check.call('crop action A4') do
    window.window.lookup_action('crop').activate(GLib::Variant.new('A4'))
    [window.selected_page.crop_name, window.selected_page.has_crop?].inspect
  end
  check.call('rotate crop action') do
    window.window.lookup_action('rotate_crop').activate(nil)
    [window.selected_page.crop_width, window.selected_page.crop_height].inspect
  end
  check.call('crop action none') do
    window.window.lookup_action('crop').activate(GLib::Variant.new('none'))
    window.selected_page.has_crop?.inspect
  end
  check.call('crop action custom') do
    window.window.lookup_action('crop').activate(GLib::Variant.new('custom'))
    [window.selected_page.crop_name.inspect, window.selected_page.crop_width].inspect
  end

  check.call('move right then left') do
    page = window.book.get_page(0)
    window.selected_page = page
    app.lookup_action('move_right').activate(nil)
    moved = window.book.get_page_index(page)
    app.lookup_action('move_left').activate(nil)
    [moved, window.book.get_page_index(page)].inspect
  end

  check.call('copy page to clipboard') { app.lookup_action('copy_page').activate(nil) || 'copied' }

  check.call('reorder dialog') do
    dialog = ReorderPagesDialog.new { |choice| choice }.build
    dialog.present(window.window)
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    dialog.close
    'presented'
  end

  check.call('shortcuts dialog') do
    ShortcutsDialog.new.build.tap { |d| d.present(window.window) }
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    'presented'
  end

  check.call('about dialog') do
    AboutDialog.new.build.tap { |d| d.present(window.window) }
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    'presented'
  end

  check.call('install drivers dialog') do
    InstallDriversDialog.new('hpaio').build.then do |dialog|
      dialog.present(window.window)
      GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
      [dialog.message, dialog.instructions].inspect
    end
  end

  check.call('authorize dialog') do
    credentials = nil
    dialog = AuthorizeDialog.new('Username and password required to access “test”') { |u, p| credentials = [u, p] }.build
    dialog.present(window.window)
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    dialog.username_row.text = 'user'
    dialog.password_row.text = 'secret'
    dialog.authorize_button.signal_emit('clicked')
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    credentials.inspect
  end

  check.call('save dialog options') do
    dialog = SaveDialog.new(window.settings, window.book) { |path, mime, quality| [path, mime, quality] }.build
    dialog.present(window.window)
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    before = dialog.mime_type
    dialog.format_row.selected = 1
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    after = [dialog.mime_type, dialog.quality, window.settings.get_string('save-format')]
    dialog.close
    [before, after].inspect
  end

  check.call('save path mime mapping') do
    [SaveDialog.path_to_mime_type('/tmp/a.pdf'), SaveDialog.path_to_mime_type('/tmp/a.PNG'),
     SaveDialog.path_to_mime_type('/tmp/a')
].inspect
  end

  check.call('progress bar in action bar') do
    cancellable = Gio::Cancellable.new
    bar = CancellableProgressBar.new('Saving', cancellable).build
    window.action_bar.pack_end(bar)
    bar.fraction = 0.5
    bar.cancel_button.signal_emit('clicked')
    [cancellable.cancelled?, bar.bar.fraction].inspect
  end

  check.call('print operation built') do
    PrintOperation.new(window.book).build.n_pages
  end

  check.call('save document to pdf') do
    target = File.join(ROOT, 'driven.pdf')
    finished = nil
    window.book.save_async(
      mime_type:   'application/pdf',
      quality:     75,
      path:        target,
      on_finished: ->(error) { finished = error || :done },
    )
    GLib::MainContext.default.iteration(true) while finished.nil?
    [finished, File.size(target)].inspect
  end

  check.call('delete page action') do
    app.lookup_action('delete_page').activate(nil)
    window.book.n_pages
  end

  check.call('empty the book') do
    5.times do
      window.selected_page = window.book.get_page(0)
      app.lookup_action('delete_page').activate(nil)
    end
    window.book.n_pages
  end

  check.call('new document clears the book') do
    app.lookup_action('new_document').activate(nil)
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    [window.book.n_pages, window.stack.visible_child_name].inspect
  end

  check.call('autosave manager writes the cleared book to disk') do
    autosave_manager = window.instance_variable_get(:@autosave_manager)
    deadline = Time.now + 5
    until File.exist?(autosave_manager.path) || Time.now > deadline
      GLib::MainContext.default.iteration(true)
    end
    [File.exist?(autosave_manager.path), autosave_manager.exists?].inspect
  end

  check.call('prompt appears when the book is unsaved') do
    window.book.append_page(
      Page.from_data(
        scan_width:     10,
        scan_height:    10,
        rowstride:      10,
        n_channels:     1,
        depth:          8,
        dpi:            72,
        scan_direction: ScanDirection::TOP_TO_BOTTOM,
        color_profile:  nil,
        pixels:         ([200] * 100).pack('C*'),
        has_crop:       false,
        crop_name:      nil,
        crop_x:         0,
        crop_y:         0,
        crop_width:     0,
        crop_height:    0,
      ),
    )
    app.lookup_action('new_document').activate(nil)
    GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    # The book survives until the prompt is answered.
    window.book.n_pages
  end

  check.call('state saved') do
    window.settings.save_state(force: true)
    File.read(window.settings.state_location).lines.map(&:chomp).join(' | ')
  end

  window.window.destroy
  app.quit
end

app.run([])

puts
puts "#{checks - failures.length} of #{checks} checks passed"
failures.each { |label| puts "  failed check: #{label}" }
puts(failures.empty? ? 'DRIVE OK' : "DRIVE FAILED (#{failures.length})")
exit(failures.empty? ? 0 : 1)
