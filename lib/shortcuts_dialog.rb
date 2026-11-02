# frozen_string_literal: true

require 'adwaita'

require_relative 'translations'

# ShortcutsDialog lists the keyboard shortcuts.
#
# Ported from upstream's data/ui/help-overlay.ui, a GtkShortcutsWindow with
# four groups. GtkShortcutsWindow cannot be constructed through the Ruby
# bindings — Gtk::ShortcutsWindow.new raises "GtkWindow is not subtype of
# GtkShortcutsWindow" — so this is the Adwaita equivalent, which takes the
# same titles and accelerators.
class ShortcutsDialog < Adwaita::ShortcutsDialog
  include Translations
  extend Translations

  SECTIONS = {
    p_('shortcut window', 'Scanning')              => [
      [p_('shortcut window', 'Scan a single page'), '<ctrl>1'],
      [p_('shortcut window', 'Scan all pages from document feeder'), '<ctrl>f'],
      [p_('shortcut window', 'Scan continuously from a flatbed scanner'), '<ctrl>m'],
      [p_('shortcut window', 'Stop scan in progress'), 'Escape'],
    ],
    p_('shortcut window', 'Document Modification') => [
      [p_('shortcut window', 'Move page left'), 'less'],
      [p_('shortcut window', 'Move page right'), 'greater'],
      [p_('shortcut window', 'Rotate page to the left (anti-clockwise)'), 'bracketleft'],
      [p_('shortcut window', 'Rotate page to the right (clockwise)'), 'bracketright'],
      [p_('shortcut window', 'Delete page'), 'Delete'],
    ],
    p_('shortcut window', 'Document Management')   => [
      [p_('shortcut window', 'Start new document'), '<ctrl>n'],
      [p_('shortcut window', 'Save scanned document'), '<ctrl>s'],
      [p_('shortcut window', 'Email scanned document'), '<ctrl>e'],
      [p_('shortcut window', 'Print scanned document'), '<ctrl>p'],
      [p_('shortcut window', 'Copy current page to clipboard'), '<ctrl>c'],
    ],
    p_('shortcut window', 'General')               => [
      [p_('shortcut window', 'Show help'), 'F1'],
      [p_('shortcut window', 'Open menu'), 'F10'],
      [p_('shortcut window', 'Keyboard shortcuts'), '<ctrl>question'],
      [p_('shortcut window', 'Quit'), '<ctrl>q'],
    ],
  }.freeze

  def initialize
    super()
    self.title = _('Keyboard Shortcuts')
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
