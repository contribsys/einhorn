module Einhorn
  class PrctlAbstract
    def self.get_pdeathsig
      raise NotImplementedError
    end

    def self.set_pdeathsig(signal)
      raise NotImplementedError
    end
  end

  class PrctlUnimplemented < PrctlAbstract
    # Deliberately empty; NotImplementedError is intended
  end

  if RUBY_PLATFORM.match?(/linux/)
    begin
      require "einhorn/prctl_linux"
      Prctl = PrctlLinux
    rescue LoadError
      Prctl = PrctlUnimplemented
    end
  else
    Prctl = PrctlUnimplemented
  end
end
