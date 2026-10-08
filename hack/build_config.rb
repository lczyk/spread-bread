#!/usr/bin/env ruby
# Pins and the build matrix from config.yaml, for the other hack scripts.
# Run as `build_config.rb --make` it prints them as make assignments, which
# the makefile includes.

require "yaml"

module BuildConfig
  CONFIG = YAML.safe_load_file(File.expand_path("../config.yaml", __dir__))

  # make passes the pins to the build in the environment, so a command-line
  # override (make CHISEL_REF=...) has to win here too.
  def self.pin(name) = ENV.fetch(name) { CONFIG.fetch("pins").fetch(name) }

  VERSIONS = CONFIG.fetch("versions").freeze
  ARCHES = CONFIG.fetch("arches").keys.freeze
  NATIVE_ARCHES = CONFIG.fetch("arches").select { |_, opts| (opts || {}).fetch("native", true) }.keys.freeze
  PUBLISHED_FLAVOURS = CONFIG.fetch("flavours").freeze
end

if $PROGRAM_NAME == __FILE__
  abort "usage: build_config.rb --make" unless ARGV == ["--make"]
  BuildConfig::CONFIG.fetch("pins").each { |name, value| puts "#{name} := #{value}" }
  puts "VERSIONS := #{BuildConfig::VERSIONS.join(" ")}"
  puts "ARCHES := #{BuildConfig::ARCHES.join(" ")}"
  puts "NATIVE_ARCHES := #{BuildConfig::NATIVE_ARCHES.join(" ")}"
end
