#!/usr/bin/env ruby
# frozen_string_literal: true

# Populate a rock dir's hack/ (and patches/ for the chisel-releases flavour)
# from the shared rocks/hack + rocks/patches.
#
# rockcraft only copies the project dir (the one with rockcraft.yaml) into the
# build instance, so each rock needs its own physical copy of the shared files
# at pack time. The per-dir copies are gitignored and regenerated from here --
# rocks/hack + rocks/patches are the single source of truth.
#
# Usage: ruby sync_shared.rb <rock-dir>

require "fileutils"

ROOT = __dir__

# Scripts every rock needs. The chisel-releases flavour also builds chisel +
# docker from source, so it gets those two extra build scripts + the patches.
COMMON  = %w[banner.txt bread-warning.sh lazy-apt.sh sshd-entry.sh hash_inputs.sh chisel_cut.sh].freeze
CR_ONLY = %w[chisel_override_build.sh docker_override_build.sh].freeze

dir = ARGV[0] or abort "usage: ruby sync_shared.rb <rock-dir>"
dest = File.join(ROOT, dir)
abort "no such rock dir: #{dir}" unless File.directory?(dest)

cr = dir.include?("chisel-releases")

FileUtils.mkdir_p(File.join(dest, "hack"))
(COMMON + (cr ? CR_ONLY : [])).each do |f|
  FileUtils.cp(File.join(ROOT, "hack", f), File.join(dest, "hack", f), preserve: true)
end

if cr
  chisel = File.join(dest, "patches", "chisel")
  FileUtils.mkdir_p(chisel)
  Dir[File.join(ROOT, "patches", "chisel", "*.patch")].each do |p|
    FileUtils.cp(p, File.join(chisel, File.basename(p)), preserve: true)
  end
end
