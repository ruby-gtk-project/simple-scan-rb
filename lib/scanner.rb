# frozen_string_literal: true

require 'adwaita'
require 'glib2'

require_relative 'page'
require_relative 'sane_api'
require_relative 'scan_options'
require_relative 'translations'

# Scanner is the backend engine: it drives libsane on a background thread and
# tells the window what happened through the signals ScanDevice, ScanLine and
# friends carry.
#
# Ported from upstream's src/scanner.vala — the ScanJob, Request* and Notify*
# classes upstream keeps private to that file are private constants here too.
# Upstream's thread talks to the main loop through two AsyncQueues and an
# Idle.add per notification; here a plain Thread talks to the main loop
# through a Thread::Queue and GLib::Idle.add, which is the same shape.
#
# SANE itself has no GObject-Introspection binding, so the calls this makes
# are through lib/sane_api.rb, a direct `ffi` binding over libsane.so.1.
class Scanner
  include Signals
  include Translations

  # Request is what the main thread pushes to the scan thread.
  Request = Struct.new(:kind, :job)

  # ScanJob is one requested scan, queued until the device is free.
  ScanJob = Struct.new(
    :id,
    :device,
    :dpi,
    :scan_mode,
    :depth,
    :type,
    :side,
    :page_width,
    :page_height,
    :brightness,
    :contrast,
    :page_delay,
    keyword_init: true,
  )

  Credentials = Struct.new(:username, :password)

  STATES = %i[idle redetect open get_option start get_parameters read].freeze

  # The names of scan modes often used in drivers, as taken from the
  # sane-backends source — upstream's do_get_option.
  COLOR_SCAN_MODES = [
    'Color', '24bit Color[Fast]', '24bit Color', '24-bit Color',
    '24 bit Color', 'Color - 16 Million Colors'
  ].freeze
  GRAY_SCAN_MODES = [
    'Gray', 'Grayscale', '8-bit Grayscale', 'True Gray',
    'Grayscale - 256 Levels'
  ].freeze
  LINEART_SCAN_MODES = [
    'Lineart', 'LineArt', 'Black & White', 'Binary', 'Thresholded',
    'Gray', 'Grayscale', 'True Gray', '1-bit Black & White',
    'Black and White - Line Art', 'Black and White - Halftone', 'Monochrome'
  ].freeze
  FLATBED_SOURCES = [
    'Auto', 'Flatbed', 'FlatBed', 'Normal', 'Document Table'
  ].freeze
  ADF_SOURCES = [
    'Automatic Document Feeder', 'ADF',
    'Automatic Document Feeder(centrally aligned)',
    'Automatic Document Feeder(center aligned)',
    'Automatic Document Feeder(left aligned)', 'ADF Simplex'
  ].freeze
  ADF_FRONT_SOURCES = ['ADF Front'].freeze
  ADF_BACK_SOURCES = ['ADF Back'].freeze
  ADF_DUPLEX_SOURCES = [
    'ADF Duplex', 'Duplex ADF', 'ADF Duplex - Long-Edge Binding',
    'ADF Duplex - Short-Edge Binding', 'Duplex',
    'Automatic Document Feeder(centrally aligned,Duplex)',
    'Automatic Document Feeder(left aligned,Duplex)'
  ].freeze

  def initialize
    @request_queue = Thread::Queue.new
    @authorize_queue = Thread::Queue.new
    @scanning = false
    @need_redetect = false
    @default_device = nil
    @first_job_id = 0
    @job_id = 0
  end

  # Public API

  def start
    @thread = Thread.new { scan_thread }
  end

  def redetect
    if @need_redetect
      nil
    else
      @need_redetect = true
      @request_queue << Request.new(:redetect)
    end
  end

  def scanning? = @scanning

  def scan(device, options)
    job = ScanJob.new(
      id:          @job_id,
      device:      device,
      dpi:         options.dpi,
      scan_mode:   options.scan_mode,
      depth:       options.depth,
      type:        options.type,
      side:        options.side,
      page_width:  options.paper_width,
      page_height: options.paper_height,
      brightness:  options.brightness,
      contrast:    options.contrast,
      page_delay:  options.page_delay,
    )
    @job_id += 1
    @request_queue << Request.new(:start_scan, job)
  end

  def cancel
    @first_job_id = @job_id
    @request_queue << Request.new(:cancel)
  end

  def authorize(username, password)
    @authorize_queue << Credentials.new(username, password)
  end

  def free
    @request_queue << Request.new(:quit)
    @thread&.join
    @thread = nil
  end

  private

    # Notifications run back on the main loop, exactly as upstream's
    # Notify.run does from its Idle.add callback.
    def notify(&block)
      GLib::Idle.add { block.call; false }
    end

    def set_scanning(is_scanning)
      if @scanning == is_scanning
        nil
      else
        @scanning = is_scanning
        notify { emit(:scanning_changed) }
      end
    end

    # Device detection

    def device_weight(name)
      if name.start_with?('vfl:')
        2
      elsif name.include?('usb')
        0
      else
        1
      end
    end

    def do_redetect
      list_pp = FFI::MemoryPointer.new(:pointer)
      status = SaneApi.sane_get_devices(list_pp, 0)
      @need_redetect = false
      @state = :idle

      if status != SaneApi::STATUS_GOOD
        warn "Unable to get SANE devices: #{SaneApi.strstatus(status)}"
      else
        devices = read_device_list(list_pp.read_pointer).sort_by { |d| [device_weight(d.name), d.label] }
        @default_device = devices.first&.name
        notify { emit(:update_devices, devices) }
      end
    end

    def read_device_list(list_ptr)
      [].tap do |devices|
        index = 0
        loop do
          entry = list_ptr.get_pointer(index * FFI::Pointer.size)
          if entry.null?
            break
          end

          devices << scan_device_from(SaneApi::Device.new(entry))
          index += 1
        end
      end
    end

    def scan_device_from(dev)
      name = dev[:name].read_string
      vendor = dev[:vendor].read_string
      model = dev[:model].read_string
      if vendor == 'Hewlett-Packard'
        vendor = 'HP'
      end
      if model.downcase.start_with?(vendor.downcase)
        label = model
      else
        label = "#{vendor} #{model}"
      end
      ScanDevice.new(name: name, label: label.tr('_', ' '))
    end

    # The scan thread

    def scan_thread
      @state = :idle
      version_pp = FFI::MemoryPointer.new(:int)
      status = SaneApi.sane_init(version_pp, nil)

      if status != SaneApi::STATUS_GOOD
        warn "Unable to initialize SANE backend: #{SaneApi.strstatus(status)}"
      else
        redetect
        run_scan_loop
      end
    end

    def run_scan_loop
      loop do
        unless handle_requests
          break
        end

        case @state
        when :idle
          if @job_queue&.any?
            set_scanning(true)
            @state = :open
          end
        when :redetect then do_redetect
        when :open then do_open
        when :get_option then do_get_option
        when :start then do_start
        when :get_parameters then do_get_parameters
        when :read then do_read
        end
      end
    end

    def handle_requests
      if @state == :idle && @need_redetect
        @state = :redetect
      end

      request_count = 0
      keep_running = true
      done = false

      until done
        if (@state == :idle && request_count.zero?) || !@request_queue.empty?
          request = @request_queue.pop
          request_count += 1
          done = !process_request(request) { keep_running = false }
        else
          done = true
        end
      end

      keep_running
    end

    # Processes one request, yielding to the block when the scan thread
    # should stop. Returns false once it has done so, which ends the request
    # loop for this turn too.
    def process_request(request)
      case request.kind
      when :start_scan
        (@job_queue ||= []).push(request.job)
        true
      when :cancel
        fail_scan(SaneApi::STATUS_CANCELLED, 'Scan cancelled - do not report this error')
        true
      when :quit
        close_device
        yield
        false
      else
        true
      end
    end

    def close_device
      if @handle
        SaneApi.sane_cancel(@handle)
        SaneApi.sane_close(@handle)
        @handle = nil
      end
      @options = nil
      @job_queue = nil
      set_scanning(false)
    end

    def fail_scan(error_code, error_string)
      close_device
      @state = :idle
      notify { emit(:scan_failed, error_code, error_string) }
    end

    def current_job = @job_queue&.first

    # Opening the device

    def do_open
      job = current_job
      @line_count = 0
      @pass_number = 0
      @page_number = 0
      @notified_page = -1

      job.device ||= @default_device

      if job.device.nil?
        warn 'No scan device available'
        fail_scan(0, _('No scanners available.  Please connect a scanner.'))
      elsif @handle && @current_device == job.device
        @state = :get_option
      else
        open_new_device(job)
      end
    end

    def open_new_device(job)
      if @handle
        SaneApi.sane_close(@handle)
        @handle = nil
      end

      @current_device = nil
      @options = {}
      handle_pp = FFI::MemoryPointer.new(:pointer)
      status = SaneApi.sane_open(FFI::MemoryPointer.from_string(job.device), handle_pp)

      if status != SaneApi::STATUS_GOOD
        warn "Unable to open device: #{SaneApi.strstatus(status)}"
        fail_scan(status, _('Unable to connect to scanner'))
      else
        @handle = handle_pp.read_pointer
        @current_device = job.device
        @option_index = 0
        @state = :get_option
      end
    end

    # Reading options and applying job settings — upstream's do_get_option.
    # The SANE option table varies wildly between drivers, hence the long
    # fallback lists above; this walks it exactly once per open, indexing by
    # name into @options so later lookups are O(1).

    def do_get_option
      descp = SaneApi.sane_get_option_descriptor(@handle, @option_index)
      index = @option_index
      @option_index += 1

      if descp.null?
        apply_job_options(current_job)
        @state = :start
      else
        option = SaneApi::OptionDescriptor.new(descp)
        name = option.name_str
        unless option[:type] == SaneApi::TYPE_GROUP || name.nil?
          @options[name] = index
        end
      end
    end

    def apply_job_options(job)
      set_source(job)
      set_scan_mode(job)
      set_duplex(job)
      set_adf_vendor_options(job)
      set_multi_page_options(job)
      set_resolution(job)
      set_scan_area(job)
      set_brightness_contrast(job)
      if @current_device == 'test'
        set_test_backend_options
      end
    end

    def set_source(job)
      index = @options['scan-source'] || @options['doc-source']
      if index.nil?
        nil
      else
        option = option_descriptor(index)
        if option.nil?
          nil
        else
          case job.type
          when ScanType::SINGLE, ScanType::BATCH
            unless set_default_option(index, option) || set_constrained_string(index, option, FLATBED_SOURCES)
              set_adf(job, index, option)
            end
          when ScanType::ADF
            set_adf(job, index, option)
          end
        end
      end
    end

    def set_adf(job, index, option)
      case job.side
      when ScanSide::FRONT
        set_constrained_string(index, option, ADF_FRONT_SOURCES) ||
          set_constrained_string(index, option, ADF_SOURCES)
      when ScanSide::BACK
        set_constrained_string(index, option, ADF_BACK_SOURCES) ||
          set_constrained_string(index, option, ADF_SOURCES)
      when ScanSide::BOTH
        set_constrained_string(index, option, ADF_DUPLEX_SOURCES) ||
          set_constrained_string(index, option, ADF_SOURCES)
      end
    end

    def set_scan_mode(job)
      index = @options['mode']
      if index.nil?
        nil
      else
        option = option_descriptor(index)
        if option.nil?
          nil
        else
          case job.scan_mode
          when ScanMode::COLOR then set_constrained_string(index, option, COLOR_SCAN_MODES)
          when ScanMode::GRAY then set_constrained_string(index, option, GRAY_SCAN_MODES)
          when ScanMode::LINEART then set_constrained_string(index, option, LINEART_SCAN_MODES)
          end
        end
      end
    end

    def set_duplex(job)
      index = @options['duplex'] || @options['scan-both-sides']
      if index.nil?
        nil
      else
        option = option_descriptor(index)
        if option.nil? || option[:type] != SaneApi::TYPE_BOOL
          nil
        else
          set_bool_option(index, job.side == ScanSide::BOTH)
        end
      end
    end

    def set_adf_vendor_options(job)
      mode_index = @options['adf-mode'] || @options['ScanMode']
      if mode_index
        option = option_descriptor(mode_index)
        if option
          if job.side == ScanSide::BOTH
            values = ['Duplex']
          else
            values = ['Simplex']
          end
          set_constrained_string(mode_index, option, values)
        end
      end

      auto_index = @options['adf-auto-scan']
      if auto_index
        option = option_descriptor(auto_index)
        if option&.[](:type) == SaneApi::TYPE_BOOL
          set_bool_option(auto_index, true)
        end
      end
    end

    def set_multi_page_options(job)
      index = @options['batch-scan']
      if index.nil?
        nil
      else
        option = option_descriptor(index)
        if option.nil? || option[:type] != SaneApi::TYPE_BOOL
          nil
        else
          set_bool_option(index, job.type != ScanType::SINGLE && job.type != ScanType::BATCH)
        end
      end
    end

    def set_resolution(job)
      x_index = @options['resolution-x']
      if x_index && (option_descriptor(x_index)[:cap] & SaneApi::CAP_SOFT_SELECT != 0)
        job.dpi = set_fixed_or_int_option(x_index, option_descriptor(x_index), job.dpi)
        y_index = @options['resolution-y']
        if y_index
          apply_resolution(y_index, job)
        end
      else
        index = @options['resolution'] || @options['scan-resolution']
        if index
          apply_resolution(index, job)
        end
      end
    end

    def apply_resolution(index, job)
      option = option_descriptor(index)
      if option.nil?
        nil
      else
        job.dpi = set_fixed_or_int_option(index, option, job.dpi)
        depth_index = @options['depth']
        if depth_index.nil? || job.depth <= 0
          nil
        else
          set_int_option(depth_index, job.depth)
        end
      end
    end

    def set_scan_area(job)
      br_x = @options['br-x']
      if br_x
        option = option_descriptor(br_x)
        if job.page_width.positive?
          set_fixed_or_int_option(br_x, option, convert_page_size(option, job.page_width, job.dpi))
        else
          set_option_to_max(br_x, option)
        end
      end

      br_y = @options['br-y']
      if br_y
        option = option_descriptor(br_y)
        if job.page_height.positive?
          set_fixed_or_int_option(br_y, option, convert_page_size(option, job.page_height, job.dpi))
        else
          set_option_to_max(br_y, option)
        end
      end

      if job.page_width.zero?
        area_index = @options['scan-area']
        if area_index
          set_string_option(area_index, 'Maximum')
        end

        auto_size_index = @options['AutoDocumentSize']
        if auto_size_index
          set_bool_option(auto_size_index, true)
        end
      end

      pw_index = @options['page-width']
      if pw_index && job.page_width.positive?
        set_fixed_or_int_option(pw_index, option_descriptor(pw_index), convert_page_size(option_descriptor(pw_index), job.page_width, job.dpi))
      end

      ph_index = @options['page-height']
      if ph_index && job.page_height.positive?
        set_fixed_or_int_option(ph_index, option_descriptor(ph_index), convert_page_size(option_descriptor(ph_index), job.page_height, job.dpi))
      end
    end

    def set_brightness_contrast(job)
      bright_index = @options['brightness']
      if bright_index
        option = option_descriptor(bright_index)
        apply_scaled_option(bright_index, option, job.brightness)
      end

      contrast_index = @options['contrast']
      if contrast_index
        option = option_descriptor(contrast_index)
        apply_scaled_option(contrast_index, option, job.contrast)
      end
    end

    def apply_scaled_option(index, option, value)
      case option[:type]
      when SaneApi::TYPE_FIXED then set_fixed_option(
        index,
        scale_fixed(
          -100,
          100,
          option,
          value,
        ),
      )
      when SaneApi::TYPE_INT then set_int_option(
        index,
        scale_int(
          -100,
          100,
          option,
          value,
        ),
      )
      end
    end

    def set_test_backend_options
      ['hand-scanner', 'three-pass'].each do |name|
        index = @options[name]
        if index
          set_bool_option(index, false)
        end
      end
      picture_index = @options['test-picture']
      if picture_index
        set_string_option(picture_index, 'Color pattern')
      end
      delay_index = @options['read-delay']
      if delay_index
        set_bool_option(delay_index, true)
      end
      duration_index = @options['read-delay-duration']
      if duration_index
        set_int_option(duration_index, 200_000)
      end
    end

    # SANE option primitives — upstream's set_*_option/scale_*/convert_page_size.

    def option_descriptor(index)
      descp = SaneApi.sane_get_option_descriptor(@handle, index)
      if descp.null?
        nil
      else
        option = SaneApi::OptionDescriptor.new(descp)
        if option[:cap] & SaneApi::CAP_INACTIVE != 0
          nil
        else
          option
        end
      end
    end

    def set_default_option(index, option)
      if option[:cap] & SaneApi::CAP_AUTOMATIC == 0
        false
      else
        status = SaneApi.sane_control_option(
          @handle,
          index,
          SaneApi::ACTION_SET_AUTO,
          nil,
          nil,
        )
        status == SaneApi::STATUS_GOOD
      end
    end

    def set_bool_option(index, value)
      v = FFI::MemoryPointer.new(:int).write_int(value ? 1 : 0)
      SaneApi.sane_control_option(
        @handle,
        index,
        SaneApi::ACTION_SET_VALUE,
        v,
        nil,
      )
    end

    def set_int_option(index, value)
      option = option_descriptor(index)
      v = value
      if option && option[:constraint_type] == SaneApi::CONSTRAINT_RANGE
        range = option.range
        if range[:quant] != 0
          v *= range[:quant]
        end
        if v < range[:min]
          v = range[:min]
        end
        if v > range[:max]
          v = range[:max]
        end
      elsif option && option[:constraint_type] == SaneApi::CONSTRAINT_WORD_LIST
        v = nearest_word(option.word_list, v)
      end
      pointer = FFI::MemoryPointer.new(:int).write_int(v)
      SaneApi.sane_control_option(
        @handle,
        index,
        SaneApi::ACTION_SET_VALUE,
        pointer,
        nil,
      )
      pointer.read_int
    end

    def set_fixed_option(index, value)
      option = option_descriptor(index)
      v = value
      if option && option[:constraint_type] == SaneApi::CONSTRAINT_RANGE
        range = option.range
        min = SaneApi.unfix(range[:min])
        max = SaneApi.unfix(range[:max])
        if v < min
          v = min
        end
        if v > max
          v = max
        end
      elsif option && option[:constraint_type] == SaneApi::CONSTRAINT_WORD_LIST
        v = nearest_fixed_word(option.word_list, v)
      end
      pointer = FFI::MemoryPointer.new(:int).write_int(SaneApi.fix(v))
      SaneApi.sane_control_option(
        @handle,
        index,
        SaneApi::ACTION_SET_VALUE,
        pointer,
        nil,
      )
      SaneApi.unfix(pointer.read_int)
    end

    def set_fixed_or_int_option(index, option, value)
      if option[:type] == SaneApi::TYPE_FIXED
        set_fixed_option(index, value)
      elsif option[:type] == SaneApi::TYPE_INT
        set_int_option(index, value.round)
      else
        warn 'Unable to set unsupported option type'
        0.0
      end
    end

    def set_option_to_max(index, option)
      if option[:constraint_type] != SaneApi::CONSTRAINT_RANGE
        nil
      else
        range = option.range
        pointer = FFI::MemoryPointer.new(:int).write_int(range[:max])
        SaneApi.sane_control_option(
          @handle,
          index,
          SaneApi::ACTION_SET_VALUE,
          pointer,
          nil,
        )
      end
    end

    def set_string_option(index, value)
      if index.nil?
        nil
      else
        option = option_descriptor(index)
        if option.nil? || option[:type] != SaneApi::TYPE_STRING
          nil
        else
          pointer = FFI::MemoryPointer.new(option[:size])
          pointer.put_bytes(0, value.b[0...(option[:size] - 1)] || '')
          SaneApi.sane_control_option(
            @handle,
            index,
            SaneApi::ACTION_SET_VALUE,
            pointer,
            nil,
          )
          status_ok = true
          status_ok
        end
      end
    end

    def set_constrained_string(index, option, candidates)
      available = option.string_list
      match = candidates.find { |value| available.include?(value) }
      if match.nil?
        false
      else
        set_string_option(index, match)
        true
      end
    end

    def nearest_word(word_list, value)
      word_list.min_by { |candidate| (candidate - value).abs } || value
    end

    def nearest_fixed_word(word_list, value)
      unfixed = word_list.map { |w| SaneApi.unfix(w) }
      unfixed.min_by { |candidate| (candidate - value).abs } || value
    end

    def scale_fixed(source_min, source_max, option, value)
      v = value.to_f
      if option[:constraint_type] != SaneApi::CONSTRAINT_RANGE
        v
      else
        range = option.range
        if range[:max] == range[:min]
          v
        else
          v -= source_min
          v *= SaneApi.unfix(range[:max]) - SaneApi.unfix(range[:min])
          v /= (source_max - source_min)
          v += SaneApi.unfix(range[:min])
          v
        end
      end
    end

    def scale_int(source_min, source_max, option, value)
      v = value
      if option[:constraint_type] != SaneApi::CONSTRAINT_RANGE
        v
      else
        range = option.range
        if range[:max] == range[:min]
          v
        else
          v -= source_min
          v *= (range[:max] - range[:min])
          v /= (source_max - source_min)
          v += range[:min]
          v
        end
      end
    end

    def convert_page_size(option, size, dpi)
      case option[:unit]
      when SaneApi::UNIT_PIXEL then dpi * size / 254.0
      when SaneApi::UNIT_MM then size / 10.0
      else
        warn 'Unable to set unsupported unit type'
        0.0
      end
    end

    # Starting the scan and reading data — upstream's do_start/do_get_parameters/do_read/do_complete_page/do_complete_document.

    def do_start
      notify { emit(:expect_page) }

      status = SaneApi.sane_start(@handle)
      if status == SaneApi::STATUS_GOOD
        @state = :get_parameters
      elsif status == SaneApi::STATUS_NO_DOCS
        job = current_job
        do_complete_document
        if job && @page_number.zero?
          fail_scan(status, _('Document feeder empty'))
        end
      elsif status == SaneApi::STATUS_NO_MEM
        fail_scan(
          status,
          _(
            "Insufficient memory to perform scan.\n" \
            'Try to decrease <tt>Resolution</tt> or <tt>Page Size</tt> in <tt>Preferences</tt> menu. ' \
            'For some scanners when scanning in high resolution, the scan size is restricted.',
          ),
        )
      elsif status == SaneApi::STATUS_DEVICE_BUSY
        # Keep waiting for the scanner rather than interrupting.
        nil
      else
        warn "Unable to start device: #{SaneApi.strstatus(status)}"
        fail_scan(status, _('Unable to start scan'))
      end
    end

    def do_get_parameters
      params = SaneApi::Parameters.new
      status = SaneApi.sane_get_parameters(@handle, params.to_ptr)

      if status != SaneApi::STATUS_GOOD
        warn "Unable to get device parameters: #{SaneApi.strstatus(status)}"
        fail_scan(status, _('Error communicating with scanner'))
      else
        accept_parameters(params)
      end
    end

    def accept_parameters(params)
      job = current_job
      info = ScanPageInfo.new(
        width:      params[:pixels_per_line],
        height:     params[:lines],
        depth:      params[:depth],
        n_channels: params[:format] == SaneApi::FRAME_GRAY ? 1 : 3,
        dpi:        job.dpi,
        device:     @current_device,
      )
      if params[:depth] == 8 && params[:format] == SaneApi::FRAME_GRAY && job.depth == 2 && job.scan_mode == ScanMode::GRAY
        info.depth = job.depth
      end

      if @page_number != @notified_page
        notify { emit(:got_page_info, info) }
        @notified_page = @page_number
      end

      @parameters = params
      @buffer = String.new.b
      @line_count = 0
      @pass_number = 0
      @state = :read
    end

    def do_read
      bytes_per_line = @parameters[:bytes_per_line]
      to_read = bytes_per_line + 1 - @buffer.bytesize
      if to_read < 1
        to_read = 1
      end

      read_buf = FFI::MemoryPointer.new(:uchar, to_read)
      len_pp = FFI::MemoryPointer.new(:int)
      status = SaneApi.sane_read(
        @handle,
        read_buf,
        to_read,
        len_pp,
      )

      handle_read_status(
        status,
        read_buf,
        len_pp.read_int,
        bytes_per_line,
      )
    end

    def handle_read_status(status, read_buf, n_read, bytes_per_line)
      if status == SaneApi::STATUS_EOF
        if @parameters[:lines].positive? && @line_count != @parameters[:lines]
          warn "Scan completed with #{@line_count} lines, expected #{@parameters[:lines]} lines"
        end
        do_complete_page
      elsif status == SaneApi::STATUS_NO_DOCS
        do_complete_document
        if @page_number.zero?
          fail_scan(status, _('Document feeder empty'))
        end
      elsif status != SaneApi::STATUS_GOOD
        warn "Unable to read frame from device: #{SaneApi.strstatus(status)}"
        fail_scan(status, _('Error communicating with scanner'))
      else
        @buffer << read_buf.read_bytes(n_read)
        feed_out_lines(current_job, bytes_per_line)
      end
    end

    def feed_out_lines(job, bytes_per_line)
      if @buffer.bytesize < bytes_per_line
        nil
      else
        n_lines = @buffer.bytesize / bytes_per_line
        line_bytes = @buffer.byteslice(0, n_lines * bytes_per_line)
        @buffer = @buffer.byteslice(n_lines * bytes_per_line..) || String.new.b
        line = ScanLine.new(
          number:      @line_count,
          n_lines:     n_lines,
          width:       @parameters[:pixels_per_line],
          depth:       @parameters[:depth],
          channel:     channel_for(@parameters[:format]),
          data:        line_bytes,
          data_length: bytes_per_line,
        )
        @line_count += n_lines
        if reduce_bit_depth?(job)
          reduce_bit_depth(line, job)
        end
        notify { emit(:got_line, line) }
      end
    end

    def channel_for(format)
      case format
      when SaneApi::FRAME_GRAY then 0
      when SaneApi::FRAME_RGB then -1
      when SaneApi::FRAME_RED then 0
      when SaneApi::FRAME_GREEN then 1
      when SaneApi::FRAME_BLUE then 2
      else -1
      end
    end

    def reduce_bit_depth?(job)
      @parameters[:depth] == 8 && @parameters[:format] == SaneApi::FRAME_GRAY &&
        job.depth == 2 && job.scan_mode == ScanMode::GRAY
    end

    # Upstream's 8-bit-to-2-bit-gray packing hack in do_read.
    def reduce_bit_depth(line, _job)
      packed = String.new.b
      line.n_lines.times do |row|
        offset = row * line.data_length
        block = 0
        shift = 6
        line.width.times do |x|
          sample = line.data.getbyte(offset + x)
          if sample >= 192
            level = 3
          elsif sample >= 128
            level = 2
          elsif sample >= 64
            level = 1
          else
            level = 0
          end
          block |= level << shift
          if shift.zero?
            packed << block.chr
            block = 0
            shift = 6
          else
            shift -= 2
          end
        end
        if shift != 6
          packed << block.chr
        end
      end
      line.data = packed
      line.data_length = ((line.width * 2) + 7) / 8
    end

    def do_complete_page
      job = current_job
      notify { emit(:page_done) }

      if @parameters[:last_frame] == 0
        @pass_number += 1
        @state = :start
      elsif job.type != ScanType::SINGLE
        if job.type == ScanType::BATCH && job.page_delay.positive?
          sleep(job.page_delay / 1000.0)
        end

        @page_number += 1
        @pass_number = 0
        notify { emit(:page_done) }
        @state = :start
      else
        do_complete_document
      end
    end

    def do_complete_document
      SaneApi.sane_cancel(@handle)
      @job_queue&.shift
      @state = :idle

      if @job_queue&.any?
        @state = :open
      else
        notify { emit(:document_done) }
        set_scanning(false)
      end
    end
end
