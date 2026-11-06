# frozen_string_literal: true

require 'ffi'

# SaneApi is the FFI binding to libsane.so.1 that lib/scanner.rb drives.
#
# SANE has no GObject-Introspection binding — unlike every other C library
# this port talks to, there is no typelib to load — so this is a direct
# binding through the `ffi` gem instead, covering only the handful of
# `sane_*` entry points upstream's src/scanner.vala calls (it is a thin Vala
# binding over the same C header, sane/sane.h).
#
# The library to dlopen is named by SIMPLE_SCAN_SANE_LIB (flake.nix sets it,
# both for the packaged app and the dev shell), falling back to the
# platform's default search names.
module SaneApi
  extend FFI::Library

  ffi_lib [ENV.fetch('SIMPLE_SCAN_SANE_LIB', nil), 'libsane.so.1', 'sane'].compact

  # SANE_Status, sane/sane.h
  STATUS_GOOD          = 0
  STATUS_UNSUPPORTED   = 1
  STATUS_CANCELLED     = 2
  STATUS_DEVICE_BUSY   = 3
  STATUS_INVAL         = 4
  STATUS_EOF           = 5
  STATUS_JAMMED        = 6
  STATUS_NO_DOCS       = 7
  STATUS_COVER_OPEN    = 8
  STATUS_IO_ERROR      = 9
  STATUS_NO_MEM        = 10
  STATUS_ACCESS_DENIED = 11

  # SANE_Value_Type
  TYPE_BOOL   = 0
  TYPE_INT    = 1
  TYPE_FIXED  = 2
  TYPE_STRING = 3
  TYPE_BUTTON = 4
  TYPE_GROUP  = 5

  # SANE_Unit
  UNIT_NONE        = 0
  UNIT_PIXEL       = 1
  UNIT_BIT         = 2
  UNIT_MM          = 3
  UNIT_DPI         = 4
  UNIT_PERCENT     = 5
  UNIT_MICROSECOND = 6

  # SANE_Constraint_Type
  CONSTRAINT_NONE       = 0
  CONSTRAINT_RANGE      = 1
  CONSTRAINT_WORD_LIST  = 2
  CONSTRAINT_STRING_LIST = 3

  # SANE_Action
  ACTION_GET_VALUE = 0
  ACTION_SET_VALUE = 1
  ACTION_SET_AUTO  = 2

  # SANE_Frame
  FRAME_GRAY  = 0
  FRAME_RGB   = 1
  FRAME_RED   = 2
  FRAME_GREEN = 3
  FRAME_BLUE  = 4

  # SANE_Cap bit flags
  CAP_SOFT_SELECT = 1
  CAP_HARD_SELECT = 2
  CAP_SOFT_DETECT = 4
  CAP_EMULATED    = 8
  CAP_AUTOMATIC   = 16
  CAP_INACTIVE    = 32
  CAP_ADVANCED    = 64

  # Fixed-point conversion, SANE_FIX/SANE_UNFIX (sane/saneopts.h): 16.16.
  def self.unfix(value) = value / 65536.0

  def self.fix(value) = (value * 65536.0).round

  # struct SANE_Device
  class Device < FFI::Struct
    layout(
      :name,
      :pointer,
      :vendor,
      :pointer,
      :model,
      :pointer,
      :type,
      :pointer,
    )
  end

  # struct SANE_Range
  class Range < FFI::Struct
    layout(
      :min,
      :int,
      :max,
      :int,
      :quant,
      :int,
    )
  end

  # struct SANE_Option_Descriptor. The constraint is a C union: which member
  # is live depends on constraint_type, read through whichever pointer is
  # asked for.
  class OptionDescriptor < FFI::Struct
    layout(
      :name,
      :pointer,
      :title,
      :pointer,
      :desc,
      :pointer,
      :type,
      :int,
      :unit,
      :int,
      :size,
      :int,
      :cap,
      :int,
      :constraint_type,
      :int,
      :constraint,
      :pointer,
    )

    def name_str = self[:name].null? ? nil : self[:name].read_string

    def title_str = self[:title].null? ? nil : self[:title].read_string

    def desc_str = self[:desc].null? ? nil : self[:desc].read_string

    def range
      Range.new(self[:constraint])
    end

    # SANE_Word word_list[]: word_list[0] is the count, word_list[1..] the
    # values (ints, or SANE_Fixed when type is FIXED — the caller unfixes).
    def word_list
      if self[:constraint].null?
        []
      else
        count = self[:constraint].get_int32(0)
        (1..count).map { |i| self[:constraint].get_int32(i * 4) }
      end
    end

    # SANE_String_Const string_list[]: a NULL-terminated array of pointers.
    def string_list
      if self[:constraint].null?
        []
      else
        values = []
        offset = 0
        loop do
          ptr = self[:constraint].get_pointer(offset)
          if ptr.null?
            break
          end

          values << ptr.read_string
          offset += FFI::Pointer.size
        end
        values
      end
    end
  end

  # struct SANE_Parameters
  class Parameters < FFI::Struct
    layout(
      :format,
      :int,
      :last_frame,
      :int,
      :bytes_per_line,
      :int,
      :pixels_per_line,
      :int,
      :lines,
      :int,
      :depth,
      :int,
    )
  end

  # SANE_Auth_Callback: void (*)(SANE_String_Const resource,
  #                              SANE_Char *username, SANE_Char *password)
  callback :auth_callback, %i[pointer pointer pointer], :void

  attach_function :sane_init, %i[pointer auth_callback], :int
  attach_function :sane_exit, [], :void
  attach_function :sane_get_devices, %i[pointer int], :int
  attach_function :sane_open, %i[pointer pointer], :int
  attach_function :sane_close, [:pointer], :void
  attach_function :sane_get_option_descriptor, %i[pointer int], :pointer
  attach_function :sane_control_option, %i[pointer int int pointer pointer], :int
  attach_function :sane_get_parameters, %i[pointer pointer], :int
  attach_function :sane_start, [:pointer], :int
  attach_function :sane_read, %i[pointer pointer int pointer], :int
  attach_function :sane_cancel, [:pointer], :void
  attach_function :sane_strstatus, [:int], :pointer

  def self.strstatus(status)
    sane_strstatus(status).read_string
  end
end
