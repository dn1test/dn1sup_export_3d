# coordinate.rb
module Dn1supExport3d
  module Exporter
    module Coordinate
      INCH_TO_METER = 0.0254

      def self.position(p)
        [p[0] * INCH_TO_METER, -p[2] * INCH_TO_METER, -p[1] * INCH_TO_METER]
      end

      def self.normal(n)
        [n[0], -n[2], -n[1]]
      end

      def self.determinant_sign(t)
        a = t.to_a
        det = (a[0] * a[5] * a[10] + a[1] * a[6] * a[8] + a[2] * a[4] * a[9]) -
              (a[2] * a[5] * a[8] + a[1] * a[4] * a[10] + a[0] * a[6] * a[9])
        det < 0 ? -1 : 1
      end
    end
  end
end
