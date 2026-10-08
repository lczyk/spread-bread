#!/usr/bin/env ruby
# Build every published image for one arch and save each as a docker-archive
# tarball, plus digests.json mapping "<flavour>:<ver>" to the image's config
# digest (hack/config_digest.rb). That identifies the image's content, so the
# publish step can compare it with what ghcr already has without the tarballs.
#
# Usage: build_images.rb <arch> <out-dir>

require "fileutils"
require "json"
require_relative "build_config"
require_relative "config_digest"

Dir.chdir(File.expand_path("..", __dir__))

arch, out = ARGV
abort "usage: build_images.rb <arch> <out-dir>" unless arch && out

def run(*cmd)
  system(*cmd) or abort "build_images: #{cmd.join(" ")} failed"
end

def tar_member(tar, name) = IO.popen(["tar", "-xOf", tar, name], &:read)

# Emulated builds are ~single-core and the per-version chains are
# independent, so build two at a time; past that they only contend for the
# runner's cores. -O keeps each image's log whole.
run("make", "-j2", "-O", "build-bread", "build-bread-chisel-releases", "ARCH=#{arch}")

FileUtils.mkdir_p(out)

digests = BuildConfig::PUBLISHED_FLAVOURS.product(BuildConfig::VERSIONS).to_h do |flavour, ver|
  tar = File.join(out, "#{flavour}-#{ver}-#{arch}.tar")
  puts "==> saving #{flavour}:#{ver}-#{arch}"
  run("docker", "save", "#{flavour}:#{ver}-#{arch}", "-o", tar)
  config = JSON.parse(tar_member(tar, "manifest.json")).fetch(0).fetch("Config")
  ["#{flavour}:#{ver}", ConfigDigest.of(tar_member(tar, config))]
end

File.write(File.join(out, "digests.json"), JSON.pretty_generate(digests) + "\n")
