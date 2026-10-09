# frozen_string_literal: true

# Packages the extension as build/dn1sup_export_3d.rbz. The archive contains
# only what the extension needs at runtime (AGENTS.md #35): the registrar at
# the archive root plus the extension folder (without test/) and LICENSE.
#
# Uses Windows bsdtar (-a picks ZIP by extension), so no gems are required:
#   ruby build/package.rb
require "fileutils"

root = File.expand_path("..", __dir__)
name = "dn1sup_export_3d"
staging = File.join(root, "build", "rbz_staging")
rbz = File.join(root, "build", "#{name}.rbz")

# The GUI bundles are built by npm (web/) and committed; packaging a stale
# or half-built tree would ship a broken extension.
%w[viewer/assets/viewer.js ui/assets/export_dialog.js].each do |asset|
  asset_path = File.join(root, name, asset)
  next if File.file?(asset_path)
  warn "Missing built asset: #{asset_path}"
  abort "Run `npm run build` in web/ first, then package again."
end

FileUtils.rm_rf(staging)
FileUtils.mkdir_p(staging)
FileUtils.cp(File.join(root, "#{name}.rb"), staging)
FileUtils.cp(File.join(root, "LICENSE"), staging)
FileUtils.cp_r(File.join(root, name), staging)
FileUtils.rm_rf(File.join(staging, name, "test"))

Dir.chdir(staging) do
  ok = system("tar", "-a", "-c", "-f", rbz, "#{name}.rb", "LICENSE", name)
  raise "tar failed - is bsdtar available on PATH?" unless ok
end
FileUtils.rm_rf(staging)
puts "Packaged #{rbz} (#{File.size(rbz)} bytes)"
