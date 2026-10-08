# frozen_string_literal: true

module Dn1supExport3d
  module Exporter
    # Centralized SketchUp -> glTF coordinate conversion (AGENTS.md #10/#11).
    #
    # SketchUp: right-handed, 1 unit = 1 inch, +Z up.
    # glTF 2.0: right-handed, 1 unit = 1 meter, +Y up, +Z toward the viewer.
    #
    # Axis mapping: (x, y, z)su -> (x, z, -y)gltf. This is a proper rotation
    # (determinant +1), so triangle winding order is preserved and mirrored
    # transformations stay mirrored (negative determinant passes through).
    module Coordinate
      INCH_TO_METER = 0.0254

      S = INCH_TO_METER
      # Basis-change matrices acting on column vectors: v_gltf = C * v_su.
      # C is a -90 degree rotation about X combined with the inch->meter scale.
      C = [[S, 0, 0, 0], [0, 0, S, 0], [0, -S, 0, 0], [0, 0, 0, 1]].freeze
      C_INV = [[1 / S, 0, 0, 0], [0, 0, -1 / S, 0], [0, 1 / S, 0, 0], [0, 0, 0, 1]].freeze

      def self.position(point)
        [point[0] * INCH_TO_METER, point[2] * INCH_TO_METER, -point[1] * INCH_TO_METER]
      end

      def self.normal(normal)
        [normal[0], normal[2], -normal[1]]
      end

      # Sign of the determinant of the linear part (mirror detection).
      def self.determinant_sign(transformation)
        a = transformation.to_a
        det = (a[0] * a[5] * a[10] + a[1] * a[6] * a[8] + a[2] * a[4] * a[9]) -
              (a[2] * a[5] * a[8] + a[1] * a[4] * a[10] + a[0] * a[6] * a[9])
        det < 0 ? -1 : 1
      end

      # Geom::Transformation -> glTF node "matrix": 16 floats, column-major,
      # in meters. The SketchUp matrix (whose to_a rows are the x/y/z axes and
      # the origin, as verified against SketchUp 2026) is conjugated with the
      # basis change: M_gltf = C * M_su * C_inv.
      def self.matrix4(transformation)
        a = transformation.to_a
        m = [
          [a[0], a[4], a[8], a[12]],
          [a[1], a[5], a[9], a[13]],
          [a[2], a[6], a[10], a[14]],
          [0.0, 0.0, 0.0, 1.0]
        ]
        result = multiply(multiply(C, m), C_INV)
        out = Array.new(16, 0.0)
        4.times { |col| 4.times { |row| out[col * 4 + row] = result[row][col] } }
        out
      end

      def self.multiply(x, y)
        (0...4).map do |i|
          (0...4).map do |j|
            (0...4).sum { |k| x[i][k] * y[k][j] }
          end
        end
      end
    end
  end
end
