#!/usr/bin/env rake
require 'bundler/gem_tasks'
require 'rake/testtask'

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
