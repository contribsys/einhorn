require "bundler/setup"
require "socket"
require "einhorn/worker"

def einhorn_main
  serv = Socket.for_fd(Einhorn::Worker.socket!)
  Einhorn::Worker.ack!
  Einhorn::Worker.ping!("id-1")

  Signal.trap("USR2") do
    sleep ENV.fetch("TRAP_SLEEP").to_i
    exit
  end

  while true
    s, _ = serv.accept
    s.write($$)
    s.flush
    s.close
  end
end

einhorn_main if $0 == __FILE__
