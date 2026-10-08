# glb_exporter.rb
require "json"
require_relative "coordinate"
require_relative "materials"
require_relative "geometry"

module Dn1supExport3d
  module Exporter
    class GLBExporter
      MAGIC = 0x46546C67
      VERSION = 2
      CHUNK_JSON = 0x4E4F534A
      CHUNK_BIN = 0x004E4942
      GENERATOR = "dn1sup_export_3d".freeze

      def initialize(model:, scope: :all)
        @model = model
        @scope = scope
      end

      def export(path)
        @material_converter = MaterialConverter.new
        @geometry = GeometryExtractor.new(@model, @material_converter)
        @geometry.extract(scope: @scope)

        nodes = build_node_tree(@model.entities)

        gltf = {
          "asset" => { "version" => "2.0", "generator" => GENERATOR },
          "scene" => 0,
          "scenes" => [{ "nodes" => [0] }],
          "nodes" => nodes,
          "meshes" => [build_mesh],
          "materials" => @material_converter.to_a,
          "accessors" => @accessors,
          "bufferViews" => @buffer_views,
          "buffers" => [{ "byteLength" => @bin_length }]
        }

        write_glb(path, gltf)
      end

      def build_node_tree(entities)
        @flat_nodes = []
        root = { "name" => @model.title.empty? ? "SketchUp Model" : @model.title, "mesh" => 0 }
        children = entity_nodes(entities)
        root["children"] = children unless children.empty?
        [root] + @flat_nodes
      end

      def entity_nodes(entities)
        nodes = []
        entities.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          next unless entity.visible? && entity.layer.visible?
          name = entity.name.to_s
          name = entity.is_a?(Sketchup::Group) ? "Group" : entity.definition.name if name.empty?
          index = @flat_nodes.size
          @flat_nodes << {
            "name" => name,
            "extras" => {
              "sketchup" => {
                "persistent_id" => entity.persistent_id,
                "entity_type" => entity.class.name.split("::").last,
                "name" => entity.name.to_s
              }
            }
          }
          inner = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
          children = entity_nodes(inner)
          @flat_nodes[index]["children"] = children unless children.empty?
          nodes << index
        end
        nodes
      end

      def build_mesh
        positions = @geometry.positions.pack("e*")
        normals = @geometry.normals.pack("e*")

        pad4 = ->(bytes) { bytes + "\0" * ((4 - bytes.bytesize % 4) % 4) }
        positions = pad4.(positions)
        normals = pad4.(normals)

        bin = positions + normals
        @bin_chunks = [bin]
        @bin_length = bin.bytesize

        @buffer_views = [
          { "buffer" => 0, "byteOffset" => 0, "byteLength" => positions.bytesize, "target" => 34962 },
          { "buffer" => 0, "byteOffset" => positions.bytesize, "byteLength" => normals.bytesize, "target" => 34962 }
        ]

        vertex_count = @geometry.positions.size / 3
        slices = @geometry.positions.each_slice(3).to_a
        min = [0, 1, 2].map { |i| slices.map { |p| p[i] }.min }
        max = [0, 1, 2].map { |i| slices.map { |p| p[i] }.max }

        @accessors = [
          { "bufferView" => 0, "componentType" => 5126, "count" => vertex_count, "type" => "VEC3", "min" => min, "max" => max },
          { "bufferView" => 1, "componentType" => 5126, "count" => @geometry.normals.size / 3, "type" => "VEC3" }
        ]

        primitives = @geometry.material_ranges.map do |mat_idx, ranges|
          indices_accessor = append_indices_accessor(ranges)
          prim = { "attributes" => { "POSITION" => 0, "NORMAL" => 1 }, "indices" => indices_accessor }
          prim["material"] = mat_idx unless mat_idx == -1
          prim
        end

        { "primitives" => primitives }
      end

      def append_indices_accessor(ranges)
        use_u32 = @geometry.positions.size / 3 > 65_535
        flat = []
        ranges.each { |offset, length| flat.concat(@geometry.indices[offset, length]) }
        bytes = flat.pack(use_u32 ? "V*" : "v*")
        bytes += "\0" * ((4 - bytes.bytesize % 4) % 4)
        view_index = @buffer_views.size
        @buffer_views << { "buffer" => 0, "byteOffset" => @bin_length, "byteLength" => bytes.bytesize, "target" => 34962 }
        @bin_chunks << bytes
        @bin_length += bytes.bytesize
        accessor_index = @accessors.size
        @accessors << { "bufferView" => view_index, "componentType" => use_u32 ? 5125 : 5123, "count" => flat.size, "type" => "SCALAR" }
        accessor_index
      end

      def write_glb(path, gltf)
        require "fileutils"
        FileUtils.mkdir_p(File.dirname(path))
        json = JSON.generate(gltf).dup.force_encoding(Encoding::BINARY)
        json += " " * ((4 - json.bytesize % 4) % 4)
        bin = @bin_chunks.join

        total = 12 + 8 + json.bytesize + 8 + bin.bytesize
        File.binwrite(path, [MAGIC, VERSION, total].pack("VVV") + [json.bytesize, CHUNK_JSON].pack("VV") + json + [bin.bytesize, CHUNK_BIN].pack("VV") + bin)
      end
    end
  end
end
