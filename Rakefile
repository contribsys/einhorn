#!/usr/bin/env rake
require "bundler/gem_tasks"
require "standard/rake"

task default: [:"standard:fix", :test]

require "bundler/setup"
require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs = ["lib"]
  t.warning = true
  t.verbose = true
  t.test_files = FileList["test/**/*.rb"].reject do |file|
    file.end_with?("_lib.rb") || file.include?("/_lib/")
  end
end
