# Hash of an image config's content rather than its bytes: pushing a
# docker-archive image to a registry re-serialises the config JSON, so its
# blob digest changes while the image does not. Sorting keys before hashing
# makes the local tarball and the registry copy agree.

require "digest"
require "json"

module ConfigDigest
  def self.of(json) = Digest::SHA256.hexdigest(JSON.generate(canonical(JSON.parse(json))))

  def self.canonical(value)
    case value
    when Hash then value.sort.to_h.transform_values { |v| canonical(v) }
    when Array then value.map { |v| canonical(v) }
    else value
    end
  end
end
