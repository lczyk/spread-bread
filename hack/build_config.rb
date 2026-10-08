# What the build scripts share. Pins and the version matrix are read from the
# makefile so there is one copy.

module BuildConfig
  MAKEFILE = File.read(File.expand_path("../makefile", __dir__))

  def self.from_makefile(name)
    MAKEFILE[/^#{name} := (.*)$/, 1] or abort "build_config: #{name} not in makefile"
  end

  # make passes the pins to the build in the environment, so a command-line
  # override (make CHISEL_REF=...) has to win here too.
  def self.pin(name) = ENV.fetch(name) { from_makefile(name) }

  VERSIONS = from_makefile("VERSIONS").split.freeze
  PUBLISHED_FLAVOURS = %w[bread bread-chisel-releases].freeze
end
