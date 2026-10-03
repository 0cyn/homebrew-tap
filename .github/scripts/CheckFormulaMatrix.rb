#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"

VERSION_PATTERN = /^\d+\.\d+\.\d+$/
SHA_PATTERN = /^[0-9a-f]{40}$/
FORMULA_PATTERN = /^binjad@(\d+\.\d+\.\d+)\.rb$/

def fail_matrix(message)
  raise "invalid binjad formula matrix: #{message}"
end

def version_tuple(version)
  fail_matrix("invalid version #{version}") unless VERSION_PATTERN.match?(version)

  version.split(".").map(&:to_i)
end

def formula_fields(path)
  match = FORMULA_PATTERN.match(path.basename.to_s)
  fail_matrix("unexpected formula filename #{path.basename}") unless match

  binary_ninja_version = match[1]
  text = path.read
  expected_class = "BinjadAT#{binary_ninja_version.delete(".")}"
  formula_class = text[/^class ([A-Za-z0-9]+) < Formula$/, 1]
  source_revision = text[/^\s+revision: "([0-9a-f]{40})",$/, 1]
  binjad_version = text[/^\s+version "(\d+\.\d+\.\d+)"$/, 1]
  formula_revision = text[/^  revision (\d+)$/, 1]
  fail_matrix("#{path.basename} has the wrong class") unless formula_class == expected_class
  fail_matrix("#{path.basename} lacks an exact source or version") unless source_revision && binjad_version
  fail_matrix("#{path.basename} lacks its Binary Ninja version") unless text.include?("requires Binary Ninja #{binary_ninja_version}")

  {
    binary_ninja_version: binary_ninja_version,
    source_revision: source_revision,
    binjad_version: binjad_version,
    formula_revision: formula_revision ? formula_revision.to_i : 0,
    development_caveat: text.include?("development build"),
  }
end

def validate_alias(root, name, version)
  path = root/"Aliases"/name
  fail_matrix("Aliases/#{name} must be a symbolic link") unless path.symlink?

  expected = Pathname("../Formula/binjad@#{version}.rb")
  fail_matrix("Aliases/#{name} must select binjad@#{version}") unless path.readlink == expected
end

root = Pathname(ARGV.fetch(0, Dir.pwd)).realpath
matrix = JSON.parse((root/".github/binjad-formulas.json").read)
fail_matrix("unsupported schema") unless matrix["schema"] == 1 && matrix["formulas"].is_a?(Hash)
binjad_version = matrix["binjadVersion"]
formula_revision = matrix["formulaRevision"]
fail_matrix("bad binjad version") unless binjad_version.is_a?(String) && VERSION_PATTERN.match?(binjad_version)
fail_matrix("bad formula revision") unless formula_revision.is_a?(Integer) && formula_revision >= 0

formulae = {}
(root/"Formula").glob("binjad@*.rb").sort.each do |path|
  fields = formula_fields(path)
  formulae[fields[:binary_ninja_version]] = fields
end
fail_matrix("formula files differ from the manifest") unless formulae.keys.sort == matrix["formulas"].keys.sort

stable_versions = []
dev_versions = []
matrix["formulas"].each do |version, record|
  version_tuple(version)
  fail_matrix("bad record for #{version}") unless record.is_a?(Hash) && %w[stable dev].include?(record["channel"])
  fail_matrix("bad API revision for #{version}") unless SHA_PATTERN.match?(record["apiRevision"].to_s)
  fail_matrix("bad source revision for #{version}") unless SHA_PATTERN.match?(record["sourceRevision"].to_s)
  fields = formulae.fetch(version)
  fail_matrix("source mismatch for #{version}") unless fields[:source_revision] == record["sourceRevision"]
  fail_matrix("binjad version mismatch for #{version}") unless fields[:binjad_version] == binjad_version
  fail_matrix("formula revision mismatch for #{version}") unless fields[:formula_revision] == formula_revision
  development = record["channel"] == "dev"
  fail_matrix("channel caveat mismatch for #{version}") unless fields[:development_caveat] == development
  (development ? dev_versions : stable_versions) << version
end

fail_matrix("expected one stable formula") unless stable_versions == [matrix["stable"]]
latest_dev = dev_versions.max_by { |version| version_tuple(version) }
fail_matrix("latestDev is not newest") unless matrix["latestDev"] == latest_dev
validate_alias(root, "binjad", matrix["stable"])
validate_alias(root, "binjad-dev", latest_dev) if latest_dev
puts "binjad formula matrix is valid"
