# frozen_string_literal: true

require 'gettext'

require_relative 'resources'

# Translations binds the simple-scan message domain and hands out the `_`,
# `n_` and `s_` lookups the rest of lib uses.
#
# Ported from upstream's po/ catalogue and the `Intl.setlocale` /
# `Intl.bindtextdomain` pair at the top of src/simple-scan.vala. Upstream's
# strings are extracted from Vala and the .ui files; here they are extracted
# from lib/*.rb and the two data/*.in files, and the msgids are kept
# character for character identical to upstream's so the 76 catalogues in po/
# keep translating them.
#
# Two ways in, because strings appear in two places:
# - `include Translations` for instance methods;
# - `extend Translations` for the frozen tables defined in a class body, such
#   as PageMenu::PAGE_SIZES, which are built once at load time.
#
# Binding happens here, at require time, which is before any class body in
# lib runs, so a table translated in a class body is translated against the
# right locale. The locale itself is the environment's — gettext reads
# LANGUAGE, LC_ALL, LC_MESSAGES and LANG the way the C library does.
#
# When no catalogue is compiled into data/locale — a fresh checkout, before
# `rake i18n:mo` — every lookup returns its msgid, which is the untranslated
# English the port would show anyway.
module Translations
  include GetText

  DOMAIN = 'simple-scan'

  bindtextdomain(DOMAIN, path: Resources.locale_dir)
end
