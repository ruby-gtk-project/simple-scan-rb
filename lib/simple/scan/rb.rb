# frozen_string_literal: true

require_relative 'rb/version'

# Simple::Scan::Rb is the gem's packaging namespace (Simple::Scan::Rb::Version::VERSION).
#
# The app itself is not namespaced this way — it is plain top-level classes
# (Settings, Scanner, AppWindow, ...) under lib/, loaded by exe/simple-scan —
# this file exists only so `require "simple/scan/rb"` (what the gemspec's
# name maps to, and what spec/spec_helper.rb requires) resolves to something.
module Simple
  module Scan
    module Rb
    end
  end
end
