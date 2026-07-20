#!/usr/bin/env ruby
# frozen_string_literal: true

# Populate a rock dir's hack/ (and patches/ for the chisel-releases flavour)
# from the shared sources, so each rock dir is hand-maintained in one place.
#
# rockcraft only copies the project dir (the one with rockcraft.yaml) into the
# build instance, so each rock needs its own physical copy of the shared files
# at pack time. The per-dir copies are gitignored and regenerated from here.
#
# Sources:
#   - repo-root hack/ + patches/chisel -- shared with the docker-image build,
#     sourced from there rather than duplicated.
#   - rocks/hack -- rock-specific helpers (incl. a rock-flavoured hash_inputs.sh
#     that differs from the root one).
#
# Usage: ruby sync_shared.rb <rock-dir>

require "fileutils"

ROOT = __dir__
REPO_ROOT = File.expand_path("..", ROOT)

# Identical to the repo-root copies -> single source there.
ROOT_HACK = %w[banner.txt bread-warning.sh lazy-apt.sh].freeze
# Rock-specific (hash_inputs.sh here differs from the root one; the rest are
# rock-only). The chisel-releases flavour also builds chisel + docker from
# source, so it gets those two extra build scripts + the patches.
ROCK_HACK = %w[sshd-entry.sh hash_inputs.sh chisel_cut.sh].freeze
CR_ONLY   = %w[chisel_override_build.sh docker_override_build.sh].freeze

dir = ARGV[0] or abort "usage: ruby sync_shared.rb <rock-dir>"
dest = File.join(ROOT, dir)
abort "no such rock dir: #{dir}" unless File.directory?(dest)

cr = dir.include?("chisel-releases")

FileUtils.mkdir_p(File.join(dest, "hack"))
ROOT_HACK.each do |f|
  FileUtils.cp(File.join(REPO_ROOT, "hack", f), File.join(dest, "hack", f), preserve: true)
end
(ROCK_HACK + (cr ? CR_ONLY : [])).each do |f|
  FileUtils.cp(File.join(ROOT, "hack", f), File.join(dest, "hack", f), preserve: true)
end

if cr
  chisel = File.join(dest, "patches", "chisel")
  FileUtils.mkdir_p(chisel)
  Dir[File.join(REPO_ROOT, "patches", "chisel", "*.patch")].each do |p|
    FileUtils.cp(p, File.join(chisel, File.basename(p)), preserve: true)
  end
end
