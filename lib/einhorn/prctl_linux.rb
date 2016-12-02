require 'ffi'

module Einhorn
  class PrctlLinux < PrctlAbstract
    extend FFI::Library
    ffi_lib FFI::Library::LIBC
    enum :option, [
      :set_pdeathsig, 1,
      :get_pdeathsig, 2,
    ]
    attach_function :prctl, [ :option, :ulong, :ulong, :ulong, :ulong ], :int

    def self.get_pdeathsig
      out = FFI::MemoryPointer.new(:int, 1)
      if prctl(:get_pdeathsig, out.address, 0, 0, 0) != 0 then
        raise SystemCallError.new("get_pdeathsig", FFI.errno)
      end

      signo = out.get_int(0)
      if signo == 0 then
        return nil
      end

      return Signal.signame(signo)
    end

    def self.set_pdeathsig(signal)
      case
      when signal == nil
        signo = 0
      when signal.instance_of?(String)
        signo = Signal.list.fetch(signal)
      else
        signo = signal
      end

      if prctl(:set_pdeathsig, signo, 0, 0, 0) != 0 then
        raise SystemCallError.new("set_pdeathsig(#{signal})", FFI.errno)
      end
    end
  end
end
