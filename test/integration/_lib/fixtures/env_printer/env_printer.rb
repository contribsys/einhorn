require "bundler/setup"
require "socket"
require "einhorn/worker"

def einhorn_main
  warn "Worker starting up!"
  serv = Socket.for_fd(ENV["EINHORN_FD_0"].to_i)
  warn "Worker has a socket"
  Einhorn::Worker.ack!
  warn "Worker sent ack to einhorn"
  $stdout.puts "Environment from #{Process.pid} is: #{ENV.inspect}"
  while true
    s, addrinfo = serv.accept
    warn "Worker got a socket!"
    output = ""
    ARGV.each do |variable_to_write|
      output += ENV[variable_to_write].to_s
    end
    s.write(output)
    s.flush
    s.close
    warn "Worker closed its socket"
  end
end

einhorn_main if $0 == __FILE__
