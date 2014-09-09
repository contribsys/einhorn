require 'bundler/setup'
require 'socket'
require 'einhorn/worker'

def einhorn_main
  serv = Socket.for_fd(Einhorn::Worker.socket!)
  Einhorn::Worker.ack!

  Signal.trap('USR2') do
    sleep 3
    exit!
  end

  while true
    s, _ = serv.accept
    s.write($$)
    s.flush
    s.close
  end
end

einhorn_main if $0 == __FILE__
