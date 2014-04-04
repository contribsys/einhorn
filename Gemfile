# Execute bundler hook if present
['~/.', '/etc/'].any? do |file|
 File.lstat(path = File.expand_path(file + 'bundle-gemfile-hook')) rescue next
 eval(File.read(path), binding, path); break true
end || source('https://rubygems.org/')

# Only needed for examples
gem 'thin-attach_socket'

# Specify your gem's dependencies in einhorn.gemspec
gemspec
