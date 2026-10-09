# frozen_string_literal: true

# Packages the extension as build/dn1sup_export_3d.rbz. The archive contains
# only what the extension needs at runtime (AGENTS.md #35): the registrar at
# the archive root plus the extension folder (without test/) and LICENSE.
#
# Uses Windows bsdtar (-a picks ZIP by extension), so no gems are required:
#   ruby build/package.rb
require "fileutils"
require "json"

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

# The Extension Store reads registry.json's version when checking updates;
# both mirrors must match VERSION (AGENTS.md #36), otherwise the store card
# would desynchronize from the shipped extension.
require File.join(root, name, "version")
%w[registry.json web/package.json].each do |mirror|
  path = File.join(root, mirror)
  abort "Missing #{path} - cannot verify the version mirror." unless File.file?(path)
  begin
    data = JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    abort "Cannot parse #{path}: #{e.message}"
  end
  mirror_version =
    if data.is_a?(Array)
      data.dig(0, "version")                 # registry.json: [ { ... } ]
    elsif data.key?("extensions")
      data.dig("extensions", 0, "version")   # registry.json: { "extensions": [...] }
    else
      data["version"]                        # web/package.json
    end
  if mirror_version != Dn1supExport3d::VERSION
    warn "#{mirror} version #{mirror_version.inspect} != VERSION #{Dn1supExport3d::VERSION}"
    abort "Bump #{mirror} to #{Dn1supExport3d::VERSION} before packaging."
  end
end

FileUtils.rm_rf(staging)
FileUtils.mkdir_p(staging)

# CI runners put GNU tar (Git for Windows) on PATH ahead of the System32
# bsdtar; GNU tar cannot write ZIP and misreads "D:\..." as a remote host.
tar_exe =
  if RUBY_PLATFORM.include?("mingw") || RUBY_PLATFORM.include?("mswin")
    File.join(ENV["WINDIR"] || "C:\\Windows", "System32", "tar.exe")
  else
    "tar"
  end

FileUtils.cp(File.join(root, "#{name}.rb"), staging)
FileUtils.cp(File.join(root, "LICENSE"), staging)
FileUtils.cp_r(File.join(root, name), staging)
FileUtils.rm_rf(File.join(staging, name, "test"))

Dir.chdir(staging) do
  ok = system(tar_exe, "-a", "-c", "-f", rbz, "#{name}.rb", "LICENSE", name)
  raise "tar failed - is bsdtar available on PATH?" unless ok
end
FileUtils.rm_rf(staging)
puts "Packaged #{rbz} (#{File.size(rbz)} bytes)"
