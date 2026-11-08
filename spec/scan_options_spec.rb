# frozen_string_literal: true

require_relative '../lib/scan_options'

# Exercises the value types and enumerations ported from upstream's
# src/scanner.vala (see lib/scan_options.rb's own header comment). These are
# plain Ruby with no GTK dependency, so this spec needs no display server and
# runs in CI as-is.
RSpec.describe 'scan_options' do
  describe ScanType do
    describe '.to_name' do
      it 'returns the string form of a known type' do
        expect(ScanType.to_name(ScanType::ADF)).to eq('adf')
      end

      it 'falls back to single for an unknown type' do
        expect(ScanType.to_name(:bogus)).to eq('single')
      end
    end

    describe '.from_name' do
      it 'finds the symbol for a known name' do
        expect(ScanType.from_name('batch')).to eq(ScanType::BATCH)
      end

      it 'warns and falls back to single for an unknown name' do
        expect { expect(ScanType.from_name('bogus')).to eq(ScanType::SINGLE) }
          .to output(/Unknown ScanType: bogus/).to_stderr
      end
    end
  end

  describe ScanSide do
    describe '.to_name' do
      it 'returns the nick for a known side' do
        expect(ScanSide.to_name(ScanSide::FRONT)).to eq('front')
      end

      it 'falls back to both for an unknown side' do
        expect(ScanSide.to_name(:bogus)).to eq('both')
      end
    end

    describe '.from_name' do
      it 'finds the symbol for a known nick' do
        expect(ScanSide.from_name('back')).to eq(ScanSide::BACK)
      end

      it 'falls back to both for an unknown nick, without warning' do
        expect { expect(ScanSide.from_name('bogus')).to eq(ScanSide::BOTH) }
          .not_to output.to_stderr
      end
    end
  end

  describe ScanDevice do
    it 'defaults to empty name and label' do
      device = ScanDevice.new
      expect([device.name, device.label]).to eq(['', ''])
    end

    it 'keeps the name and label it was built with' do
      device = ScanDevice.new(name: 'test:0', label: 'Virtual device')
      expect([device.name, device.label]).to eq(['test:0', 'Virtual device'])
    end
  end

  describe ScanOptions do
    it 'defaults to the DEFAULT scan mode, SINGLE type and BOTH side' do
      options = ScanOptions.new
      expect([options.scan_mode, options.type, options.side, options.depth]).to eq(
        [ScanMode::DEFAULT, ScanType::SINGLE, ScanSide::BOTH, 8],
      )
    end

    it 'exposes every field the window and scanner read and write' do
      options = ScanOptions.new
      options.dpi = 300
      options.paper_width = 2100
      options.paper_height = 2970
      options.brightness = 10
      options.contrast = -10
      options.page_delay = 500

      expect(
        [options.dpi, options.paper_width, options.paper_height, options.brightness, options.contrast,
         options.page_delay],
      ).to eq([300, 2100, 2970, 10, -10, 500])
    end
  end

  describe ScanPageInfo do
    it 'defaults depth to 8 and n_channels to 1' do
      info = ScanPageInfo.new
      expect([info.depth, info.n_channels]).to eq([8, 1])
    end
  end

  describe ScanLine do
    it 'defaults to an empty line with no data' do
      line = ScanLine.new
      expect([line.n_lines, line.channel, line.data, line.data_length]).to eq([1, -1, '', 0])
    end
  end
end
