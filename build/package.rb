# frozen_string_literal: true

# Packages the extension as build/dn1sup_export_3d.rbz. The archive contains
# only what the extension needs at runtime (AGENTS.md #35): the registrar at
# the archive root plus the extension folder (without test/).
#
# Uses Windows bsdtar (-a picks ZIP by extension), so no gems are required:
#   ruby build/package.rb
require "fileutils"

root = File.expand_path("..", __dir__)
name = "dn1sup_export_3d"
staging = File.join(root, "build", "rbz_staging")
rbz = File.join(root, "build", "#{name}.rbz")

FileUtils.rm_rf(staging)
FileUtils.mkdir_p(staging)
FileUtils.cp(File.join(root, "#{name}.rb"), staging)
FileUtils.cp_r(File.join(root, name), staging)
FileUtils.rm_rf(File.join(staging, name, "test"))

Dir.chdir(staging) do
  ok = system("tar", "-a", "-c", "-f", rbz, "#{name}.rb", name)
  raise "tar failed - is bsdtar available on PATH?" unless ok
end
FileUtils.rm_rf(staging)
puts "Packaged #{rbz} (#{File.size(rbz)} bytes)"
