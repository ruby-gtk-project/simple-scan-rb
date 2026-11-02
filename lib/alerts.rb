# frozen_string_literal: true

require 'adwaita'

# Alerts builds the error and confirmation dialogs the window raises.
#
# Ported from show_error_dialog, prompt_to_save_async, check_overwrite and
# prompt_to_load_autosaved_book in upstream's src/app-window.vala. Upstream
# runs a Gtk.MessageDialog and blocks on the answer; GTK4 has no run, so each
# of these takes the block to call with the response instead.
module Alerts
  SAVE = 'save'
  DISCARD = 'discard'
  CANCEL = 'cancel'
  REPLACE = 'replace'
  YES = 'yes'
  NO = 'no'
  CLOSE = 'close'

  # Upstream's show_error_dialog.
  def self.error(parent, title, text)
    Adwaita::AlertDialog.new(title, nil).tap do |dialog|
      dialog.body_use_markup = true
      dialog.body = text.to_s
      dialog.add_response(CLOSE, '_Close')
      dialog.default_response = CLOSE
      dialog.close_response = CLOSE
      dialog.choose(parent, nil) { nil }
    end
  end

  # Upstream's prompt_to_save_async. The block is handed :save, :discard or
  # :cancel, the three answers upstream switches on.
  def self.prompt_to_save(parent, title, discard_label, &on_response)
    Adwaita::AlertDialog.new(title, nil).tap do |dialog|
      # Text in dialog warning when a document is about to be lost
      dialog.body = 'If you don’t save, changes will be permanently lost.'
      dialog.add_response(DISCARD, discard_label)
      dialog.add_response(CANCEL, '_Cancel')
      dialog.add_response(SAVE, '_Save')
      dialog.set_response_appearance(DISCARD, :destructive)
      dialog.set_response_appearance(SAVE, :suggested)
      dialog.default_response = SAVE
      dialog.close_response = CANCEL
      dialog.choose(parent, nil) { |_d, result| on_response.call(answer(dialog, result)) }
    end
  end

  # Upstream's check_overwrite, asked once per file that already exists.
  def self.confirm_overwrite(parent, basename, &on_response)
    Adwaita::AlertDialog.new(
      # Contents of dialog that shows if saving would overwrite an existing file
      format('A file named “%s” already exists.  Do you want to replace it?', basename),
      nil,
    ).tap do |dialog|
      dialog.add_response(CANCEL, '_Cancel')
      # Button in dialog that shows if saving would overwrite an existing file
      dialog.add_response(REPLACE, '_Replace')
      dialog.set_response_appearance(REPLACE, :destructive)
      dialog.default_response = CANCEL
      dialog.close_response = CANCEL
      dialog.choose(parent, nil) { |_d, result| on_response.call(answer(dialog, result) == :replace) }
    end
  end

  # Upstream's prompt_to_load_autosaved_book.
  def self.confirm_load_autosave(parent, &on_response)
    Adwaita::AlertDialog.new(
      # Contents of dialog that shows if an autosaved book should be loaded
      'An autosaved book exists. Do you want to open it?',
      nil,
    ).tap do |dialog|
      dialog.add_response(NO, '_No')
      dialog.add_response(YES, '_Yes')
      dialog.set_response_appearance(YES, :suggested)
      dialog.default_response = YES
      dialog.close_response = NO
      dialog.choose(parent, nil) { |_d, result| on_response.call(answer(dialog, result) == :yes) }
    end
  end

  # The response id as a symbol. A dialog dismissed with Escape finishes with
  # an error rather than a response, which counts as the close response.
  def self.answer(dialog, result)
    dialog.choose_finish(result).to_s.then { |response| response.empty? ? :cancel : response.to_sym }
  rescue StandardError
    dialog.close_response.to_s.to_sym
  end
end
