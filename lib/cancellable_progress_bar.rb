# frozen_string_literal: true

require 'gtk4'

# CancellableProgressBar is the progress bar with a Cancel button beside it
# that appears in the action bar while a document is being saved.
#
# Ported from the private class of the same name at the foot of upstream's
# src/app-window.vala.
class CancellableProgressBar < Gtk::Box
  def initialize(text, cancellable)
    super(:horizontal, 6)
    @text = text
    @cancellable = cancellable
  end

  def build
    tap do |box|
      box.append(bar)

      unless @cancellable.nil?
        box.append(cancel_button)

        cancel_button.signal_connect('clicked') do
          box.visible = false
          @cancellable.cancel
        end
      end
    end
  end

  def fraction=(fraction)
    bar.fraction = fraction
  end

  # Upstream's destroy_with_delay: leave the finished bar up long enough to be
  # seen, with its cancel button already dead.
  def destroy_with_delay(delay)
    cancel_button.sensitive = false
    GLib::Timeout.add(delay) do
      parent.then do |container|
        unless container.nil?
          container.remove(self)
        end
      end
      false
    end
  end

  # Memoized widget methods

  def bar
    @bar ||= Gtk::ProgressBar.new.tap do |progress|
      progress.text = @text
      progress.show_text = true
      progress.valign = :center
    end
  end

  def cancel_button
    @cancel_button ||= Gtk::Button.new.tap do |button|
      # Text of button for cancelling save
      button.label = 'Cancel'
      button.valign = :center
    end
  end
end
