module Einhorn::Event
  class Timer
    attr_reader :time

    def initialize(time, start = nil, &blk)
      @time = time
      @start = start || Time.now
      @blk = blk
    end

    # TODO: abstract into some interface
    def self.open(*args, &blk)
      instance = new(*args, &blk)
      instance.register!
      instance
    end

    def expires_at
      @start + @time
    end

    def ring!
      now = Time.now
      Einhorn.log_debug("Ringing timer that was scheduled #{now - @start}s ago and expired #{now - expires_at}s ago")
      deregister!
      @blk.call
    end

    def register!
      Einhorn.log_debug("Scheduling a new #{time}s timer")
      Einhorn::Event.register_timer(self)
    end

    def deregister!
      Einhorn.log_debug("Nuking timer that expired #{Time.now - expires_at}s ago")
      Einhorn::Event.deregister_timer(self)
    end
  end
end
