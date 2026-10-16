# frozen_string_literal: true
# =============================================================================
# tools/make_icons.rb — генерация иконки Export 3D для тулбара:
#   • векторный SVG: dn1sup_export_3d/icons/export.svg;
#   • растровые PNG: dn1sup_export_3d/icons/export_16.png, export_24.png
#   (рендеринг чистым Ruby с 4x суперсэмплингом и антиалиасингом).
#
#   ruby tools/make_icons.rb
# =============================================================================

require "zlib"
require "fileutils"

SVG_CONTENT = <<~SVG
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
    <defs>
      <linearGradient id="e3dBadge" x1="0%" y1="0%" x2="0%" y2="100%"><stop offset="0%" stop-color="#22c55e"/><stop offset="100%" stop-color="#16a34a"/></linearGradient>
    </defs>
    <path d="M12 3.5 18 7 12 10.5 6 7Z" fill="#5AB8F5" stroke="#ffffff" stroke-width=".6" stroke-linejoin="round"/>
    <path d="M6 7 12 10.5V19L6 15.5Z" fill="#0c8ee9" stroke="#ffffff" stroke-width=".6" stroke-linejoin="round"/>
    <path d="M18 7 12 10.5V19l6-3.5Z" fill="#015995" stroke="#ffffff" stroke-width=".6" stroke-linejoin="round"/>
    <circle cx="17" cy="17" r="4.6" fill="url(#e3dBadge)" stroke="#ffffff" stroke-width="1"/>
    <path d="M14.8 19.2l4.4-4.4" stroke="#ffffff" stroke-width="1.5" stroke-linecap="round"/>
    <path d="M15.8 14.8h3.4v3.4" fill="none" stroke="#ffffff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>
SVG

# -- PNG сборщик -------------------------------------------------------------

def png_chunk(type, data)
  [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
end

def write_png(path, pixels, width, height)
  raw = pixels.map { |row| "\x00" + row.map { |px| px.pack("C4") }.join }.join
  # NOTE: IHDR — строго 13 байт (N2 + C5); вариант pack("N5") из
  # dn1sup_create_project даёт 20 байт и невалидный PNG — здесь исправлено.
  png = "\x89PNG\r\n\x1a\n".b +
        png_chunk("IHDR", [width, height].pack("N2") + [8, 6, 0, 0, 0].pack("C5")) +
        png_chunk("IDAT", Zlib::Deflate.deflate(raw, Zlib::BEST_COMPRESSION)) +
        png_chunk("IEND", "")
  File.binwrite(path, png)
  puts "  ✓ #{File.basename(path)} (#{width}x#{height})"
end

# -- Канва с альфа-блендингом -------------------------------------------------

class ImageBuffer
  attr_reader :w, :h, :pixels

  def initialize(w, h)
    @w = w
    @h = h
    @pixels = Array.new(h) { Array.new(w) { [0, 0, 0, 0] } }
  end

  def blend_pixel(x, y, r, g, b, a)
    return if x < 0 || x >= @w || y < 0 || y >= @h || a <= 0

    cur = @pixels[y][x]
    sa = a / 255.0
    da = cur[3] / 255.0
    out_a = sa + da * (1.0 - sa)
    return if out_a.zero?

    out_r = ((r * sa + cur[0] * da * (1.0 - sa)) / out_a).round.clamp(0, 255)
    out_g = ((g * sa + cur[1] * da * (1.0 - sa)) / out_a).round.clamp(0, 255)
    out_b = ((b * sa + cur[2] * da * (1.0 - sa)) / out_a).round.clamp(0, 255)
    @pixels[y][x] = [out_r, out_g, out_b, (out_a * 255).round.clamp(0, 255)]
  end

  # Сглаженный спуск (4x бокс-фильтр) в результирующий буфер
  def downsample(scale = 4)
    target_w = @w / scale
    target_h = @h / scale
    out = Array.new(target_h) { Array.new(target_w) { [0, 0, 0, 0] } }

    target_h.times do |ty|
      target_w.times do |tx|
        sum_r = 0.0
        sum_g = 0.0
        sum_b = 0.0
        sum_a = 0.0

        scale.times do |sy|
          scale.times do |sx|
            px = @pixels[ty * scale + sy][tx * scale + sx]
            a = px[3] / 255.0
            sum_r += px[0] * a
            sum_g += px[1] * a
            sum_b += px[2] * a
            sum_a += a
          end
        end

        count = (scale * scale).to_f
        avg_a = sum_a / count
        if avg_a > 0.001
          avg_r = (sum_r / sum_a).round.clamp(0, 255)
          avg_g = (sum_g / sum_a).round.clamp(0, 255)
          avg_b = (sum_b / sum_a).round.clamp(0, 255)
          out[ty][tx] = [avg_r, avg_g, avg_b, (avg_a * 255).round.clamp(0, 255)]
        end
      end
    end
    out
  end
end

# -- Геометрические помощники ------------------------------------------------

def in_poly?(pts, x, y)
  inside = false
  j = pts.length - 1
  pts.length.times do |i|
    xi, yi = pts[i]
    xj, yj = pts[j]
    if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi.to_f) + xi
      inside = !inside
    end
    j = i
  end
  inside
end

def dist_seg(px, py, ax, ay, bx, by)
  dx = bx - ax
  dy = by - ay
  len_sq = dx * dx + dy * dy
  t = len_sq.zero? ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len_sq).clamp(0.0, 1.0)
  cx = ax + t * dx
  cy = ay + t * dy
  Math.sqrt((px - cx)**2 + (py - cy)**2)
end

# -- Рендеринг иконки высокого разрешения (на сетке 24 x 24) ------------------

def render_icon(target_size)
  scale = 4
  hires = target_size * scale
  buf = ImageBuffer.new(hires, hires)
  s = hires / 24.0

  top_face   = [[12.0, 3.5], [18.0, 7.0], [12.0, 10.5], [6.0, 7.0]]
  left_face  = [[6.0, 7.0], [12.0, 10.5], [12.0, 19.0], [6.0, 15.5]]
  right_face = [[18.0, 7.0], [12.0, 10.5], [12.0, 19.0], [18.0, 15.5]]

  hires.times do |y|
    ny = y / s
    hires.times do |x|
      nx = x / s

      # 1. Три грани куба: верх #5AB8F5, левая #0c8ee9, правая #015995
      if in_poly?(top_face, nx, ny)
        buf.blend_pixel(x, y, 0x5A, 0xB8, 0xF5, 255)
      elsif in_poly?(left_face, nx, ny)
        buf.blend_pixel(x, y, 0x0C, 0x8E, 0xE9, 255)
      elsif in_poly?(right_face, nx, ny)
        buf.blend_pixel(x, y, 0x01, 0x59, 0x95, 255)
      end

      # 2. Зелёный круг-бейдж: центр (17,17), r=4.6, градиент #22c55e→#16a34a
      dx = nx - 17.0
      dy = ny - 17.0
      if dx * dx + dy * dy <= 4.6 * 4.6
        # Белая стрелка наружу: отрезок + уголок (ширина 1.5)
        on_shaft = dist_seg(nx, ny, 14.8, 19.2, 19.2, 14.8) <= 0.75
        on_arm_h = dist_seg(nx, ny, 15.8, 14.8, 19.2, 14.8) <= 0.75
        on_arm_v = dist_seg(nx, ny, 19.2, 14.8, 19.2, 18.2) <= 0.75
        if on_shaft || on_arm_h || on_arm_v
          buf.blend_pixel(x, y, 255, 255, 255, 255)
        else
          t = ((dy + 4.6) / 9.2).clamp(0.0, 1.0)
          r = (0x22 * (1 - t) + 0x16 * t).round
          g = (0xC5 * (1 - t) + 0xA3 * t).round
          b = (0x5E * (1 - t) + 0x4A * t).round
          buf.blend_pixel(x, y, r, g, b, 255)
        end
      end
    end
  end

  buf.downsample(scale)
end

# -- Генерация файлов в папке icons ------------------------------------------

out = File.join(__dir__, "..", "dn1sup_export_3d", "icons")
FileUtils.mkdir_p(out)
puts "Генерация иконок в #{out}:"

# 1. SVG вектор
svg_path = File.join(out, "export.svg")
File.write(svg_path, SVG_CONTENT, encoding: "UTF-8")
puts "  ✓ export.svg (Vector)"

# 2. PNG размеры
[16, 24].each do |size|
  px = render_icon(size)
  write_png(File.join(out, "export_#{size}.png"), px, size, size)
end

puts "\nГотово! Все иконки успешно созданы."
