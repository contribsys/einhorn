require "bundler/setup"
require "socket"
require "einhorn/worker"

def einhorn_main
  version = File.read(File.join(File.dirname(__FILE__), "version"))
  warn "Worker starting up!"
  serv = Socket.for_fd(ENV["EINHORN_FD_0"].to_i)
  warn "Worker has a socket"
  Einhorn::Worker.ack!
  warn "Worker sent ack to einhorn"
  Einhorn::Worker.ping!("id-1")
  warn "Worker has sent a ping to einhorn"
  while true
    s, addrinfo = serv.accept
    warn "Worker got a socket!"
    s.write(version)
    s.flush
    s.close
    warn "Worker closed its socket"
  end
end

einhorn_main if $0 == __FILE__
