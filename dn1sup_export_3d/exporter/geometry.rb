# geometry.rb
module Dn1supExport3d
  module Exporter
    class GeometryExtractor
      attr_reader :positions, :normals, :indices, :material_ranges

      def initialize(model, material_converter)
        @model = model
        @material_converter = material_converter
        @positions = []
        @normals = []
        @indices = []
        @material_ranges = Hash.new { |h, k| h[k] = [] }
        @warned = {}
      end

      def extract(scope: :all)
        roots = scope == :selection ? @model.selection.to_a : @model.entities.to_a
        roots.each { |e| process(e, Geom::Transformation.new, false) }
        self
      end

      def process(entity, transform, mirrored)
        case entity
        when Sketchup::Group, Sketchup::ComponentInstance
          return unless visible?(entity)
          child_transform = transform * entity.transformation
          child_mirrored = (Coordinate.determinant_sign(entity.transformation) < 0) ^ mirrored
          inner = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
          inner.each { |e| process(e, child_transform, child_mirrored) }
        when Sketchup::Face
          return unless visible?(entity)
          add_face(entity, transform, mirrored)
        end
      end

      def visible?(entity)
        return false unless entity.visible?
        layer = entity.layer
        !layer || layer.visible?
      end

      def add_face(face, transform, mirrored)
        mat_idx = @material_converter.index(face.material) || -1
        mesh = face.mesh

        normal = face.normal.transform(transform).normalize
        nx, ny, nz = Coordinate.normal(normal.to_a.map { |v| v.to_f })

        (1..mesh.count_polygons).each do |i|
          poly = mesh.polygon_at(i)
          pts = mesh.polygon_points_at(i)
          next if pts.size < 3
          warn_once("Face #{face.persistent_id}: inner loops exported as outer contour only") if poly.any? { |vi| vi < 0 }

          base = @positions.size / 3
          pts.each do |p|
            wp = Coordinate.position((transform * p).to_a.map { |v| v.to_f })
            @positions.concat(wp)
            @normals.concat([nx, ny, nz])
          end
          n = pts.size
          order = (0...n).to_a
          order.reverse! if mirrored
          first_tri = @indices.size
          (1...(n - 1)).each do |k|
            @indices.concat([base + order[0], base + order[k], base + order[k + 1]])
          end
          @material_ranges[mat_idx] << [first_tri, @indices.size - first_tri]
        end
      end

      def warn_once(msg)
        return if @warned[msg]
        @warned[msg] = true
        warn("dn1sup_export_3d: #{msg}")
      end
    end
  end
end
