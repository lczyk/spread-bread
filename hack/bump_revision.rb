#!/usr/bin/env ruby
# Bump REVISION (r<N> -> r<N+1>) and commit it as "release: r<N+1>".
#
# Run by bump-revision.yaml after a PR merge, or by hand on main to cut a
# release; pushing the commit fires release.yaml. Refuses to run with
# uncommitted changes to tracked files, so the commit only ever holds the bump.
#
# `bump_revision.rb --pending [<rev>]` only checks whether a release is due:
# exits 0 if release inputs (hack/hash_inputs.rb release) changed between the
# last REVISION change and <rev> (default HEAD), 1 if not.

Dir.chdir(File.expand_path("..", __dir__))

def git(*args)
  out = IO.popen(["git", *args], &:read)
  abort "bump_revision: git #{args.join(" ")} failed" unless $?.success?
  out
end

if ARGV[0] == "--pending"
  rev = ARGV[1] || "HEAD"
  last = git("log", "-1", "--format=%H", rev, "--", "REVISION").strip
  specs = IO.popen(["hack/hash_inputs.rb", "release"], &:read).split
  abort "bump_revision: hack/hash_inputs.rb release failed" unless $?.success?
  exit(!system("git", "diff", "--quiet", last, rev, "--", *specs))
end

abort "bump_revision: working tree not clean" unless git("status", "--porcelain", "--untracked-files=no").empty?

content = File.read("REVISION")
current = content[/^r(\d+)$/, 1] or abort "bump_revision: no r<N> line in REVISION"
next_rev = "r#{current.to_i + 1}"

File.write("REVISION", content.sub(/^r\d+$/, next_rev))
git("commit", "--quiet", "--message", "release: #{next_rev}", "--", "REVISION")
puts next_rev
