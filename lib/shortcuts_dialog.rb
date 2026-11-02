# frozen_string_literal: true

require 'adwaita'

# ShortcutsDialog lists the keyboard shortcuts.
#
# Ported from upstream's data/ui/help-overlay.ui, a GtkShortcutsWindow with
# four groups. GtkShortcutsWindow cannot be constructed through the Ruby
# bindings — Gtk::ShortcutsWindow.new raises "GtkWindow is not subtype of
# GtkShortcutsWindow" — so this is the Adwaita equivalent, which takes the
# same titles and accelerators.
class ShortcutsDialog < Adwaita::ShortcutsDialog
  SECTIONS = {
    'Scanning'              => [
      ['Scan a single page', '<ctrl>1'],
      ['Scan all pages from document feeder', '<ctrl>f'],
      ['Scan continuously from a flatbed scanner', '<ctrl>m'],
      ['Stop scan in progress', 'Escape'],
    ],
    'Document Modification' => [
      ['Move page left', 'less'],
      ['Move page right', 'greater'],
      ['Rotate page to the left (anti-clockwise)', 'bracketleft'],
      ['Rotate page to the right (clockwise)', 'bracketright'],
      ['Delete page', 'Delete'],
    ],
    'Document Management'   => [
      ['Start new document', '<ctrl>n'],
      ['Save scanned document', '<ctrl>s'],
      ['Email scanned document', '<ctrl>e'],
      ['Print scanned document', '<ctrl>p'],
      ['Copy current page to clipboard', '<ctrl>c'],
    ],
    'General'               => [
      ['Show help', 'F1'],
      ['Open menu', 'F10'],
      ['Keyboard shortcuts', '<ctrl>question'],
      ['Quit', '<ctrl>q'],
    ],
  }.freeze

  def initialize
    super()
    self.title = 'Keyboard Shortcuts'
  end

  def build
    tap do |dialog|
      SECTIONS.each { |title, items| dialog.add(section(title, items)) }
    end
  end

  private

    def section(title, items)
      Adwaita::ShortcutsSection.new.tap do |section|
        section.title = title
        items.each { |label, accelerator| section.add(item(label, accelerator)) }
      end
    end

    # Positional, not keyword, arguments, even though the error a no-argument
    # new raises advertises the signatures as "title: utf8, accelerator: utf8".
    def item(label, accelerator) = Adwaita::ShortcutsItem.new(label, accelerator)
end
