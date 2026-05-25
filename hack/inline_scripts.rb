#!/usr/bin/env ruby
# Inline `source scripts/<name>.sh` references inside spread yaml templates.
#
# For each line matching `allocate: source scripts/<name>.sh` or
# `discard: source scripts/<name>.sh`, substitute the script's content as a
# yaml block scalar under the matching key.

require "fileutils"

LINE_RE = /\A(?<indent>\s*)(?<key>allocate|discard):\s*source\s+(?<path>scripts\/[\w.-]+\.sh)\s*\z/

def inline_scripts(content, yaml_indent: 2)
  out = []
  content.each_line(chomp: true) do |line|
    m = LINE_RE.match(line)
    unless m
      out << line
      next
    end
    script_path = m[:path]
    raise "Referenced script not found: #{script_path}" unless File.exist?(script_path)
    out << "#{m[:indent]}#{m[:key]}: |"
    body_indent = m[:indent] + " " * yaml_indent
    File.read(script_path).each_line(chomp: true) do |script_line|
      out << (script_line.empty? ? body_indent.rstrip : body_indent + script_line)
    end
  end
  out.join("\n") + "\n"
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.length != 2
    warn "usage: #{$PROGRAM_NAME} <input.yaml.in> <output.yaml>"
    exit 2
  end
  input, output = ARGV
  unless File.exist?(input)
    warn "Error: #{input} does not exist."
    exit 1
  end
  FileUtils.mkdir_p(File.dirname(output))
  File.write(output, inline_scripts(File.read(input)))
  warn "Processed #{input} -> #{output}"
end
