#!/usr/bin/env ruby
# Publish the multiarch images to a registry, skipping tags whose images are
# already there. "Already there" means every arch's config digest (from
# build_images.rb's digests.json) matches what the tag points at, so a tag
# left half-done by an earlier failed release is pushed again.
#
# Usage:
#   publish_images.rb plan <dir> <repo> <plan.json>   read-only: decide what to push
#   publish_images.rb push <dir> <repo> <plan.json>   push the planned tags
#   publish_images.rb sign <repo> <plan.json> [--dry-run]
#
# <dir> holds the downloaded artefacts: image-digests-<arch>/digests.json for
# plan, images-<arch>/<flavour>-<ver>-<arch>.tar for push. <repo> is e.g.
# ghcr.io/lczyk/spread-bread. sign signs pushed tags; skipped ones are only
# signed if their existing signature doesn't verify.

require "digest"
require "json"
require "open3"
require_relative "config_digest"

def run(*cmd)
  system(*cmd) or abort "publish_images: #{cmd.join(" ")} failed"
end

# Raw bytes from the registry, or nil if the reference doesn't exist. Other
# failures are retried: reading one as "missing" would re-push for nothing.
def skopeo_raw(ref, *flags)
  err = nil
  3.times do |attempt|
    sleep(2**attempt) if attempt > 0
    out, err, status = Open3.capture3("skopeo", "inspect", "--raw", *flags, "docker://#{ref}")
    return out if status.success?
    return nil if err.include?("manifest unknown")
  end
  abort "publish_images: skopeo inspect #{ref} failed: #{err}"
end

# The arch -> config digest map a tag points at, and its manifest list digest.
def remote(repo, tag)
  flavour, ver = tag.split(":")
  raw = skopeo_raw("#{repo}/#{flavour}:#{ver}") or return [{}, nil]
  configs = JSON.parse(raw).fetch("manifests", []).filter_map do |m|
    config = skopeo_raw("#{repo}/#{flavour}@#{m["digest"]}", "--config") or next
    [m.dig("platform", "architecture"), ConfigDigest.of(config)]
  end
  [configs.to_h, "sha256:#{Digest::SHA256.hexdigest(raw)}"]
end

def plan(dir, repo, out)
  local = Dir[File.join(dir, "image-digests-*", "digests.json")].to_h do |f|
    [File.basename(File.dirname(f)).delete_prefix("image-digests-"), JSON.parse(File.read(f))]
  end
  abort "publish_images: no image-digests-*/digests.json under #{dir}" if local.empty?

  tags = local.values.flat_map(&:keys).uniq.sort
  result = tags.to_h do |tag|
    want = local.transform_values { |d| d.fetch(tag) }
    have, digest = remote(repo, tag)
    push = have != want
    puts "#{push ? "push" : "skip"} #{tag}"
    [tag, {"push" => push, "digest" => (push ? nil : digest)}]
  end
  File.write(out, JSON.pretty_generate(result) + "\n")

  any = result.values.any? { |t| t["push"] }
  File.write(ENV["GITHUB_OUTPUT"], "push=#{any}\n", mode: "a") if ENV["GITHUB_OUTPUT"]
end

def push(dir, repo, plan_file)
  plan = JSON.parse(File.read(plan_file))
  arches = Dir[File.join(dir, "images-*")].map { |d| File.basename(d).delete_prefix("images-") }.sort
  plan.each do |tag, entry|
    next unless entry["push"]
    flavour, ver = tag.split(":")
    list = "#{flavour}-#{ver}-manifest"
    digest_file = File.join(dir, "#{flavour}-#{ver}.digest")
    run("buildah", "manifest", "create", list)
    arches.each do |arch|
      run("buildah", "manifest", "add", "--arch", arch, list,
          "docker-archive:#{File.join(dir, "images-#{arch}", "#{flavour}-#{ver}-#{arch}.tar")}")
    end
    run("buildah", "manifest", "push", "--format", "oci", "--all", "--digestfile", digest_file,
        list, "docker://#{repo}/#{flavour}:#{ver}")
    run("buildah", "manifest", "rm", list)
    entry["digest"] = File.read(digest_file).strip
  end
  File.write(plan_file, JSON.pretty_generate(plan) + "\n")
end

def sign(repo, plan_file, dry_run)
  identity = "^https://github\\.com/#{repo.split("/", 2).last}/\\.github/workflows/"
  JSON.parse(File.read(plan_file)).each do |tag, entry|
    ref = "#{repo}/#{tag.split(":").first}@#{entry.fetch("digest") or abort "publish_images: no digest for #{tag}"}"
    unless entry["push"]
      verified = system("cosign", "verify", "--certificate-identity-regexp", identity,
                        "--certificate-oidc-issuer", "https://token.actions.githubusercontent.com",
                        ref, out: File::NULL, err: File::NULL)
      if verified
        puts "signed already #{tag}"
        next
      end
    end
    puts "#{dry_run ? "would sign" : "signing"} #{tag}"
    run("cosign", "sign", "--yes", ref) unless dry_run
  end
end

USAGE = "usage: publish_images.rb plan|push <dir> <repo> <plan.json> | sign <repo> <plan.json> [--dry-run]"

cmd, *args = ARGV
dry_run = !args.delete("--dry-run").nil?
case [cmd, args.size]
when ["plan", 3] then plan(*args)
when ["push", 3] then push(*args)
when ["sign", 2] then sign(*args, dry_run)
else abort USAGE
end
