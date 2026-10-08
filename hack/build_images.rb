#!/usr/bin/env ruby
# Build every published image for one arch and save each as a docker-archive
# tarball, plus digests.json mapping "<flavour>:<ver>" to the image's config
# digest (hack/config_digest.rb). That identifies the image's content, so the
# publish step can compare it with what ghcr already has without the tarballs.
#
# Usage: build_images.rb <arch> <out-dir>

require "json"
require_relative "config_digest"

Dir.chdir(File.expand_path("..", __dir__))

arch, out = ARGV
abort "usage: build_images.rb <arch> <out-dir>" unless arch && out

def run(*cmd)
  system(*cmd) or abort "build_images: #{cmd.join(" ")} failed"
end

# Emulated builds are ~single-core and the per-version chains are
# independent, so build two at a time; past that they only contend for the
# runner's cores. -O keeps each image's log whole.
run("make", "-j2", "-O", "build-bread", "build-bread-chisel-releases", "ARCH=#{arch}")

versions = File.read("makefile")[/^VERSIONS := (.*)$/, 1].split
Dir.mkdir(out) unless Dir.exist?(out)

digests = %w[bread bread-chisel-releases].product(versions).to_h do |flavour, ver|
  tar = File.join(out, "#{flavour}-#{ver}-#{arch}.tar")
  puts "==> saving #{flavour}:#{ver}-#{arch}"
  run("docker", "save", "#{flavour}:#{ver}-#{arch}", "-o", tar)
  config = JSON.parse(IO.popen(["tar", "-xOf", tar, "manifest.json"], &:read)).fetch(0).fetch("Config")
  ["#{flavour}:#{ver}", ConfigDigest.of(IO.popen(["tar", "-xOf", tar, config], &:read))]
end

File.write(File.join(out, "digests.json"), JSON.pretty_generate(digests) + "\n")
