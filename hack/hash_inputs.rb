#!/usr/bin/env ruby
# Input hashes for the build: a sha256 over every file that shapes an
# artefact. Drives make's stamps, ci's cache keys and the release gate, so
# the file lists below are the one place that says what a build depends on.
#
# Usage:
#   hash_inputs.rb <flavour>-<ver>-<arch>   one image (make stamp)
#   hash_inputs.rb binaries-<arch>          the cross-compiled go binaries
#   hash_inputs.rb images-<arch>            every published image for an arch
#   hash_inputs.rb release                  pathspecs whose changes need a release
#
# Prints the hex digest, or for release one pathspec per line.

require "digest"
require_relative "build_config"

Dir.chdir(File.expand_path("..", __dir__))

BREAD_FILES = %w[
  hack/bread-warning.sh hack/banner.txt hack/tar-shim.sh hack/seccomp-shim.c hack/apt-mirror.sh
].freeze
CHISEL_FILES = %w[hack/lazy-apt.sh hack/apt-mirror.sh].freeze
BINARIES_SCRIPT = "hack/build_binaries.sh"
# How images are built and saved, as opposed to what goes into them.
IMAGE_BUILD_SCRIPTS = %w[hack/build_image.sh hack/build_images.rb hack/build_config.rb].freeze

def sha256(text) = Digest::SHA256.hexdigest(text)

# One `sha256sum`-format line, so digests match the old bash stamps.
def file_line(path) = "#{Digest::SHA256.file(path).hexdigest}  #{path}\n"

# A dependency's digest stands in for its stamp file ("<digest>\n").
def stamp_line(name, digest) = "#{sha256("#{digest}\n")}  .stamp/#{name}\n"

def binaries(arch)
  files = [BINARIES_SCRIPT, *Dir["patches/chisel/*.patch"].sort]
  pins = %w[CHISEL_REF SPREAD_REF GO_BUILDER_IMAGE DOCKER_VERSION].map { |v| "#{v}=#{BuildConfig.pin(v)}\n" }
  sha256(files.map { |f| file_line(f) }.join + "ARCH=#{arch}\n" + pins.join)
end

# Images built FROM bread:<ver> with the go binaries copied in.
def bread_deps(ver, arch)
  [stamp_line("bread-#{ver}-#{arch}", image("bread", ver, arch)), stamp_line("binaries-#{arch}", binaries(arch))]
end

def image(flavour, ver, arch)
  lines =
    case flavour
    when "bread"
      ["images/Dockerfile.bread-#{ver}", *BREAD_FILES].map { |f| file_line(f) }
    when "bread-chisel-releases"
      ["images/Dockerfile.bread-chisel-releases-#{ver}", *CHISEL_FILES].map { |f| file_line(f) } + bread_deps(ver, arch)
    when "bread-test"
      [file_line("tests/Dockerfile.bread-test-#{ver}"), *bread_deps(ver, arch)]
    else
      abort "hash_inputs: unknown flavour: #{flavour}"
    end
  sha256(lines.join)
end

# The images, plus how they're saved and digested (the digests are cached
# alongside the tarballs).
def images(arch)
  lines = BuildConfig::PUBLISHED_FLAVOURS.product(BuildConfig::VERSIONS).map do |flavour, ver|
    "#{image(flavour, ver, arch)}  #{flavour}-#{ver}-#{arch}\n"
  end
  sha256(lines.join + [*IMAGE_BUILD_SCRIPTS, "hack/config_digest.rb"].map { |f| file_line(f) }.join)
end

# Pathspecs rather than files, so `git diff` also sees deletions.
def release
  ["images/", "templates/", "scripts/", "patches/", "makefile", "hack/inline_scripts.rb",
   BINARIES_SCRIPT, *BREAD_FILES, *CHISEL_FILES, *IMAGE_BUILD_SCRIPTS].uniq
end

name = ARGV.fetch(0) { abort "usage: hash_inputs.rb <flavour-ver-arch>|binaries-<arch>|images-<arch>|release" }

case name
when "release"
  puts release
when /\Abinaries-(\w+)\z/
  puts binaries($1)
when /\Aimages-(\w+)\z/
  puts images($1)
when /\A(.+)-([\d.]+)-(\w+)\z/
  puts image($1, $2, $3)
else
  abort "hash_inputs: cannot parse #{name}"
end
