#!/usr/bin/env rake
require 'bundler/gem_tasks'
require 'rake/testtask'

desc 'Rebuild the README with the latest usage from einhorn'
task :readme do
  Dir.chdir(File.dirname(__FILE__))
  readme = File.read('README.md.in')
  usage = `bin/einhorn -h`
  readme.gsub!('[[usage]]', usage)
  File.open('README.md', 'w') {|f| f.write(readme)}
end

task :default => :test do
end
require 'bundler/setup'
require 'chalk-rake/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs = ['lib']
  # t.warning = true
  t.verbose = true
  t.test_files = FileList['test/**/*.rb'].reject do |file|
    file.end_with?('_lib.rb') || file.include?('/_lib/')
  end
end
