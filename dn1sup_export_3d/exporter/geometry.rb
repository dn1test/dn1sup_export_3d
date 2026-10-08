# frozen_string_literal: true

require_relative "coordinate"
require_relative "buffer"

module Dn1supExport3d
  module Exporter
    # Triangulated geometry of one container (model / group / component
    # definition), expressed in the container's LOCAL coordinate system and
    # grouped by material. Node transformations live in the glTF node tree,
    # not in the vertex data.
    #
    # Triangulation comes from SketchUp's own PolygonMesh (face.mesh), which
    # handles convex, concave and holed faces (verified against SketchUp 2026:
    # the sum of triangle areas equals face.area for holed faces). Vertex
    # deduplication is deliberately not done (correctness first, AGENTS.md #16).
    class MeshData
      F32 = ->(v) { [v].pack("e").unpack1("e") }.freeze

      attr_reader :triangle_count, :face_count

      def initialize(materials)
        @materials = materials
        @positions = []
        @normals = []
        @uvs = []
        @has_uvs = false
        @indices = []
        @groups = []
        @triangle_count = 0
        @face_count = 0
      end

      def empty?
        @indices.empty?
      end

      def vertex_count
        @positions.size / 3
      end

      def add_face(face)
        mat_index = @materials.index(face.material)
        texture = face.material&.texture
        has_texture = !mat_index.nil? && texture.respond_to?(:valid?) && texture.valid?
        @has_uvs = true if has_texture

        mesh = face.mesh
        normal = Coordinate.normal(face.normal.to_a.map(&:to_f))
        uv_helper = has_texture ? face.get_UVHelper(true, true) : nil

        group = {
          "material" => mat_index,
          "uv" => has_texture,
          "vertex_start" => vertex_count,
          "index_start" => @indices.size,
          "min" => nil,
          "max" => nil
        }

        (1..mesh.count_polygons).each do |i|
          points = mesh.polygon_points_at(i)
          next if points.size < 3
          base = vertex_count
          points.each do |point|
            pos = Coordinate.position(point.to_a.map(&:to_f)).map { |v| F32.call(v) }
            append_vertex(pos, normal, uv_helper, point)
            update_bounds(group, pos)
          end
          (1...(points.size - 1)).each { |k| @indices << base << (base + k) << (base + k + 1) }
        end

        return self if @indices.size == group["index_start"] # degenerate face

        group["vertex_count"] = vertex_count - group["vertex_start"]
        group["index_count"] = @indices.size - group["index_start"]
        @groups << group
        @triangle_count += group["index_count"] / 3
        @face_count += 1
        self
      end

      # Packs all vertex/index streams into the GLBBuffer and returns the glTF
      # mesh hash. Each material group becomes one primitive with its own
      # accessors into the shared, tightly packed bufferViews.
      def build_mesh(buffer)
        position_view = buffer.add_view(@positions.pack("e*"), target: GLBBuffer::TARGET_ARRAY_BUFFER)
        normal_view = buffer.add_view(@normals.pack("e*"), target: GLBBuffer::TARGET_ARRAY_BUFFER)
        uv_view = @has_uvs ? buffer.add_view(@uvs.pack("e*"), target: GLBBuffer::TARGET_ARRAY_BUFFER) : nil

        use_u32 = vertex_count > 65_535
        index_component = use_u32 ? GLBBuffer::COMPONENT_UNSIGNED_INT : GLBBuffer::COMPONENT_UNSIGNED_SHORT
        index_width = use_u32 ? 4 : 2
        # Indices are global across the mesh, but each primitive addresses
        # vertices through its own POSITION accessor, so rebase every group's
        # slice to its local vertex range before packing (same total count,
        # hence the per-group byteOffsets below stay valid).
        rebased = @groups.flat_map do |group|
          base = group["vertex_start"]
          @indices[group["index_start"], group["index_count"]].map { |index| index - base }
        end
        index_view = buffer.add_view(use_u32 ? rebased.pack("V*") : rebased.pack("v*"),
                                     target: GLBBuffer::TARGET_ELEMENT_ARRAY_BUFFER)

        primitives = @groups.map do |group|
          attributes = {
            "POSITION" => buffer.add_accessor(
              position_view,
              component_type: GLBBuffer::COMPONENT_FLOAT,
              count: group["vertex_count"], type: "VEC3",
              byte_offset: group["vertex_start"] * 12,
              min: group["min"], max: group["max"]
            ),
            "NORMAL" => buffer.add_accessor(
              normal_view,
              component_type: GLBBuffer::COMPONENT_FLOAT,
              count: group["vertex_count"], type: "VEC3",
              byte_offset: group["vertex_start"] * 12
            )
          }
          if group["uv"]
            attributes["TEXCOORD_0"] = buffer.add_accessor(
              uv_view,
              component_type: GLBBuffer::COMPONENT_FLOAT,
              count: group["vertex_count"], type: "VEC2",
              byte_offset: group["vertex_start"] * 8
            )
          end
          primitive = {
            "attributes" => attributes,
            "indices" => buffer.add_accessor(
              index_view,
              component_type: index_component,
              count: group["index_count"], type: "SCALAR",
              byte_offset: group["index_start"] * index_width
            )
          }
          primitive["material"] = group["material"] unless group["material"].nil?
          primitive
        end

        { "primitives" => primitives }
      end

      private

      def append_vertex(pos, normal, uv_helper, point)
        @positions.concat(pos)
        @normals.concat(normal.map { |v| F32.call(v) })
        if @has_uvs
          # UV stream must stay parallel to the vertex stream for every face
          # of the mesh; faces of untextured materials just get zeros (their
          # primitives do not reference TEXCOORD_0).
          if uv_helper
            uvq = uv_helper.get_front_UVQ(point)
            # glTF's V axis points down (top-left UV origin); SketchUp's points
            # up (bottom-left origin), hence the 1 - v flip.
            @uvs << F32.call(uvq.x / uvq.z) << F32.call(1.0 - uvq.y / uvq.z)
          else
            @uvs << 0.0 << 0.0
          end
        end
      end

      def update_bounds(group, pos)
        if group["min"].nil?
          group["min"] = pos.dup
          group["max"] = pos.dup
        else
          3.times do |i|
            group["min"][i] = pos[i] if pos[i] < group["min"][i]
            group["max"][i] = pos[i] if pos[i] > group["max"][i]
          end
        end
      end
    end
  end
end
