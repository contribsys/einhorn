require "bundler/setup"
require "socket"
require "einhorn/worker"
require "einhorn/prctl"

def einhorn_main
  serv = Socket.for_fd(Einhorn::Worker.socket!)

  Signal.trap("USR2") { exit }

  begin
    output = Einhorn::Prctl.get_pdeathsig
    if output.nil?
      output = "nil"
    end
  rescue NotImplementedError
    output = "not implemented"
  end

  Einhorn::Worker.ack!
  loop do
    s, _ = serv.accept
    s.write(output)
    s.flush
    s.close
  end
end

einhorn_main if $0 == __FILE__
