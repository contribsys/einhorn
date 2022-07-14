module Einhorn::Event
  module Persistent
    @@persistent = {}

    def self.included(other)
      @@persistent[other.to_s] = other
    end

    def self.from_state(state)
      klass_name = state[:class]
      if (klass = @@persistent[klass_name])
        klass.from_state(state)
      else
        Einhorn.log_error("Unrecognized persistent descriptor class #{klass_name.inspect}. Ignoring. This most likely indicates that your Einhorn version has upgraded. Everything should still be working, but it may be worth a restart.", :upgrade)
        nil
      end
    end

    def self.persistent?(descriptor)
      @@persistent.values.any? { |klass| descriptor.is_a?(klass) }
    end
  end
end
