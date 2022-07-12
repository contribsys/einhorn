require "fiddle"
require "fiddle/import"

module Einhorn
  module PrctlRaw
    extend Fiddle::Importer
    dlload Fiddle.dlopen(nil) # libc
    extern "int prctl(int, unsigned long, unsigned long, unsigned long, unsigned long)"

    # From linux/prctl.h
    SET_PDEATHSIG = 1
    GET_PDEATHSIG = 2
  end

  class PrctlLinux < PrctlAbstract
    # Reading integers is hard with fiddle. :(
    IntStruct = Fiddle::CStructBuilder.create(Fiddle::CStruct, [Fiddle::TYPE_INT], ["i"])

    def self.get_pdeathsig
      out = IntStruct.malloc
      out.i = 0
      if PrctlRaw.prctl(PrctlRaw::GET_PDEATHSIG, out.to_i, 0, 0, 0) != 0
        raise SystemCallError.new("get_pdeathsig", Fiddle.last_error)
      end

      signo = out.i
      if signo == 0
        return nil
      end

      Signal.signame(signo)
    end

    def self.set_pdeathsig(signal)
      signo = if signal.nil?
        0
      elsif signal.instance_of?(String)
        Signal.list.fetch(signal)
      else
        signal
      end

      if PrctlRaw.prctl(PrctlRaw::SET_PDEATHSIG, signo, 0, 0, 0) != 0
        raise SystemCallError.new("set_pdeathsig(#{signal})", Fiddle.last_error)
      end
    end
  end
end
