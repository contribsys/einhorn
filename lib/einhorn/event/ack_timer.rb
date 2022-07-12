module Einhorn::Event
  class ACKTimer < Timer
    include Persistent

    def initialize(time, pid, start = nil)
      super(time, start) do
        Einhorn::Command.register_timer_ack(time, pid)
      end
      @pid = pid
    end

    def to_state
      {class: self.class.to_s, time: @time, start: @start, pid: @pid}
    end

    def self.from_state(state)
      self.open(state[:time], state[:pid], state[:start])
    end
  end
end
