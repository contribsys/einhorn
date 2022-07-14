#!/usr/bin/env ruby
#
# Used as an example of preloading in Einhorn blog post
# (https://stripe.com/blog/meet-einhorn). Program name ends in .rb in
# order to make explicit that it's written in Ruby, though this isn't
# actually necessary for preloading to work.
#
# Run as
#
# einhorn -p ./pool_worker.rb ./pool_worker.rb

puts "From PID #{$$}: loading #{__FILE__}"

def einhorn_main
  loop do
    puts "From PID #{$$}: Doing some work"
    sleep 1
  end
end
