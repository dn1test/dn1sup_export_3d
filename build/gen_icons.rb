# frozen_string_literal: true

# Generates the toolbar icons (isometric cube glyph) as PNGs without gems.
# Run once from the repo root:  ruby build/gen_icons.rb
require "zlib"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
OUT_DIR = File.join(ROOT, "dn1sup_export_3d", "icons")

def write_png(path, width, height, pixels)
  rows = Array.new(height) do |y|
    row = [0]
    width.times { |x| row.concat(pixels[y * width + x]) }
    row.pack("C*")
  end
  idat = Zlib::Deflate.deflate(rows.join)
  chunk = lambda do |type, data|
    [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
  end
  png = String.new("\x89PNG\r\n\x1a\n".b, encoding: Encoding::BINARY)
  png << chunk.call("IHDR", [width, height, 8, 6, 0, 0, 0].pack("NNCCCCC"))
  png << chunk.call("IDAT", idat)
  png << chunk.call("IEND", "")
  File.binwrite(path, png)
  puts "wrote #{path} (#{File.size(path)} bytes)"
end

# Even-odd point-in-polygon test for triangle rasterization.
def point_in_triangle(px, py, ax, ay, bx, by, cx, cy)
  d1 = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
  d2 = (cx - bx) * (py - by) - (cy - by) * (px - bx)
  d3 = (ax - cx) * (py - cy) - (ay - cy) * (px - cx)
  has_neg = d1 < 0 || d2 < 0 || d3 < 0
  has_pos = d1 > 0 || d2 > 0 || d3 > 0
  !(has_neg && has_pos)
end

def draw_cube(size)
  w = size.to_f
  # Isometric cube hexagon vertices (y grows downward).
  top    = [w * 0.50, w * 0.06]
  right  = [w * 0.94, w * 0.28]
  bottom = [w * 0.94, w * 0.72]
  low    = [w * 0.50, w * 0.94]
  left   = [w * 0.06, w * 0.72]
  upper  = [w * 0.06, w * 0.28]
  center = [w * 0.50, w * 0.50]

  faces = [
    [[top, right, center], [127, 178, 232, 255]],   # top (light)
    [[top, center, upper], [127, 178, 232, 255]],
    [[right, bottom, low], [47, 111, 190, 255]],    # right (primary)
    [[right, low, center], [47, 111, 190, 255]],
    [[center, low, left], [28, 78, 145, 255]],      # left (dark)
    [[center, left, upper], [28, 78, 145, 255]]
  ]

  pixels = Array.new(size * size) { [0, 0, 0, 0] }
  size.times do |y|
    size.times do |x|
      px = x + 0.5
      py = y + 0.5
      faces.each do |(a, b, c), color|
        if point_in_triangle(px, py, a[0], a[1], b[0], b[1], c[0], c[1])
          pixels[y * size + x] = color
          break
        end
      end
    end
  end
  pixels
end

FileUtils.mkdir_p(OUT_DIR)
require "fileutils"
write_png(File.join(OUT_DIR, "export_16.png"), 16, 16, draw_cube(16))
write_png(File.join(OUT_DIR, "export_24.png"), 24, 24, draw_cube(24))
