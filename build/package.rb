# frozen_string_literal: true

# Packages the extension as build/dn1sup_export_3d.rbz. The archive contains
# only what the extension needs at runtime (AGENTS.md #35): the registrar at
# the archive root plus the extension folder (without test/) and LICENSE.
#
# Pure-Ruby ZIP writer (stdlib zlib only — no gems, no external tools):
#   ruby build/package.rb
#
# NOTE: do NOT pack with bsdtar (`tar -a`, incl. System32 tar.exe): its ZIP
# output extracts fine with libarchive but SketchUp 2026 rejects it at
# install ("Could not unzip archive" — verified live 2026-10-15, minimal
# 2-file probe; the same tree packed with .NET Deflate installs fine).

require "fileutils"
require "json"
require "zlib"

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
require File.join(root, name, "version.rb")
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

FileUtils.cp(File.join(root, "#{name}.rb"), staging)
FileUtils.cp(File.join(root, "LICENSE"), staging)
FileUtils.cp_r(File.join(root, name), staging)
FileUtils.rm_rf(File.join(staging, name, "test"))
# Служебные dot-файлы рабочей копии в прод-архив не попадают.
Dir.children(File.join(staging, name)).each do |child|
  FileUtils.rm_f(File.join(staging, name, child)) if child.start_with?(".")
end

# --- minimal ZIP writer (empty dir entries, deflated files) ----------------
# Only what an RBZ needs: stored directory entries + deflate compression via
# stdlib zlib. Deterministic order (sorted), UTF-8 flag set, DOS timestamps.

def dos_datetime(time)
  t = time.getlocal
  [(t.hour << 11) | (t.min << 5) | (t.sec / 2),
   ((t.year - 1980) << 9) | (t.month << 5) | t.day]
end

def deflate_raw(data)
  deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
  out = deflater.deflate(data, Zlib::FINISH)
  deflater.close
  out
end

def write_zip(src_dir, dest_path)
  entries = []
  Dir.chdir(src_dir) do
    Dir.glob("**/*", File::FNM_DOTMATCH).sort.each do |rel|
      next if rel == "." || rel == ".." || rel.end_with?("/.") || rel.end_with?("/..")

      full = File.join(src_dir, rel)
      zip_name = rel.tr("\\", "/")
      if File.directory?(full)
        entries << { name: "#{zip_name}/", dir: true, mtime: File.mtime(full) }
      elsif File.file?(full)
        entries << { name: zip_name, dir: false, data: File.binread(full), mtime: File.mtime(full) }
      end
    end
  end

  File.open(dest_path, "wb") do |f|
    central = []
    entries.each do |e|
      name = e[:name].encode(Encoding::UTF_8)
      dostime, dosdate = dos_datetime(e[:mtime])
      if e[:dir]
        crc = 0
        raw = "".b
        method = 0
        ext_attr = 0x10
      else
        crc = Zlib.crc32(e[:data])
        raw = deflate_raw(e[:data])
        method = 8
        ext_attr = 0x20
      end
      offset = f.pos
      f.write("PK\x03\x04")
      f.write([20, 0x0800, method, dostime, dosdate, crc, raw.bytesize,
               e[:dir] ? 0 : e[:data].bytesize, name.bytesize, 0].pack("v5V3v2"))
      f.write(name)
      f.write(raw)
      central << [name, method, dostime, dosdate, crc, raw.bytesize,
                  e[:dir] ? 0 : e[:data].bytesize, ext_attr, offset]
    end
    cd_start = f.pos
    central.each do |name, method, dostime, dosdate, crc, comp, uncomp, ext_attr, offset|
      f.write("PK\x01\x02")
      f.write([20, 20, 0x0800, method, dostime, dosdate, crc, comp, uncomp,
               name.bytesize, 0, 0, 0, 0, ext_attr, offset].pack("v6V3v5V2"))
      f.write(name)
    end
    cd_size = f.pos - cd_start
    f.write("PK\x05\x06")
    f.write([0, 0, central.size, central.size, cd_size, cd_start, 0].pack("v4V2v"))
  end
end

write_zip(staging, rbz)
FileUtils.rm_rf(staging)
puts "Packaged #{rbz} (#{File.size(rbz)} bytes)"
