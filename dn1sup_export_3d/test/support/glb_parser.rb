# frozen_string_literal: true

# Pure-Ruby GLB/glTF reader used by the test suite and by build/check_glb.rb.
# Runs anywhere Ruby runs (inside SketchUp or standalone) - no SketchUp API.
require "json"

module Dn1supTest
  # Defined here so the parser (and build/check_glb.rb) work standalone,
  # without loading the rest of the test harness.
  class TestFailure < StandardError; end

  class GLBParser
    attr_reader :gltf, :bin, :path

    CHUNK_JSON = 0x4E4F534A
    CHUNK_BIN = 0x004E4942
    COMPONENT_FLOAT = 5126
    COMPONENT_UNSIGNED_SHORT = 5123
    COMPONENT_UNSIGNED_INT = 5125
    COMPONENTS_PER_TYPE = { "SCALAR" => 1, "VEC2" => 2, "VEC3" => 3, "VEC4" => 4 }.freeze
    COMPONENT_SIZE = { COMPONENT_FLOAT => 4, COMPONENT_UNSIGNED_SHORT => 2, COMPONENT_UNSIGNED_INT => 4 }.freeze

    def self.parse(path)
      raise TestFailure, "GLB file not found: #{path}" unless File.exist?(path)
      data = File.binread(path)
      raise TestFailure, "GLB too small (#{data.bytesize} bytes)" if data.bytesize < 12
      magic, version, total = data.unpack("a4VV")
      raise TestFailure, "bad magic #{magic.inspect}" unless magic == "glTF"
      raise TestFailure, "bad version #{version} (expected 2)" unless version == 2
      unless total == data.bytesize
        raise TestFailure, "header total #{total} != file size #{data.bytesize}"
      end

      offset = 12
      json = nil
      bin = String.new(encoding: Encoding::BINARY)
      while offset < data.bytesize
        raise TestFailure, "truncated chunk header at #{offset}" if offset + 8 > data.bytesize
        length, type = data[offset, 8].unpack("VV")
        if offset + 8 + length > data.bytesize
          raise TestFailure, "chunk at #{offset} overruns file (#{length} bytes)"
        end
        body = data[offset + 8, length]
        case type
        when CHUNK_JSON then json = JSON.parse(body.force_encoding(Encoding::UTF_8))
        when CHUNK_BIN then bin << body
        end
        offset += 8 + length
      end
      raise TestFailure, "GLB has no JSON chunk" unless json
      new(json, bin, path)
    end

    def initialize(gltf, bin, path)
      @gltf = gltf
      @bin = bin
      @path = path
    end

    # Decodes an accessor into a flat array of numbers.
    def accessor_data(index)
      accessor = @gltf["accessors"][index]
      raise TestFailure, "no accessor #{index}" unless accessor
      view = @gltf["bufferViews"][accessor["bufferView"]]
      raise TestFailure, "accessor #{index}: no bufferView" unless view
      base = view["byteOffset"].to_i + accessor["byteOffset"].to_i
      components = COMPONENTS_PER_TYPE[accessor["type"]]
      raise TestFailure, "accessor #{index}: bad type" unless components
      count = accessor["count"] * components
      case accessor["componentType"]
      when COMPONENT_FLOAT then @bin[base, count * 4].unpack("e*")
      when COMPONENT_UNSIGNED_SHORT then @bin[base, count * 2].unpack("v*")
      when COMPONENT_UNSIGNED_INT then @bin[base, count * 4].unpack("V*")
      else raise TestFailure, "accessor #{index}: unsupported componentType"
      end
    end

    def position_accessor_indices
      @position_accessor_indices ||= (@gltf["meshes"] || []).flat_map do |mesh|
        mesh["primitives"].map { |p| p["attributes"]["POSITION"] }
      end.uniq
    end

    # Structural validation per the glTF 2.0 spec subset this exporter uses.
    # Returns an array of error strings; empty means valid.
    def validate
      errors = []
      validate_scene_and_nodes(errors)
      validate_meshes(errors)
      validate_accessors(errors)
      validate_buffer(errors)
      errors
    end

    # Geometric normal (b-a)x(c-a) must agree with the interpolated vertex
    # normals for every triangle (CCW winding when viewed from the normal).
    def winding_matches_normals?(primitive)
      positions = accessor_data(primitive["attributes"]["POSITION"])
      normals = accessor_data(primitive["attributes"]["NORMAL"])
      indices = accessor_data(primitive["indices"])
      (0...indices.size).step(3).all? do |i|
        a, b, c = indices[i, 3].map { |vi| [positions[vi * 3], positions[vi * 3 + 1], positions[vi * 3 + 2]] }
        u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]]
        v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]]
        n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
        len = Math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
        next true if len.zero? # degenerate triangle: skip
        normals[i * 3, 3].zip(n).sum { |nv, w| nv * w }.positive?
      end
    end

    def triangle_area_sum(primitive)
      positions = accessor_data(primitive["attributes"]["POSITION"])
      indices = accessor_data(primitive["indices"])
      sum = 0.0
      (0...indices.size).step(3).each do |i|
        a, b, c = indices[i, 3].map { |vi| [positions[vi * 3], positions[vi * 3 + 1], positions[vi * 3 + 2]] }
        u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]]
        v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]]
        n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
        sum += Math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]) / 2.0
      end
      sum
    end

    private

    def validate_scene_and_nodes(errors)
      scenes = @gltf["scenes"]
      unless scenes.is_a?(Array) && !scenes.empty?
        errors << "no scenes array"
        return
      end
      scene = scenes[@gltf["scene"] || 0]
      errors << "missing scene" unless scene
      nodes = @gltf["nodes"] || []
      (scene ? scene["nodes"] : []).each do |n|
        errors << "scene references invalid node #{n}" unless n.is_a?(Integer) && n >= 0 && n < nodes.size
      end
      nodes.each_with_index do |node, i|
        next unless node.is_a?(Hash)
        (node["children"] || []).each do |c|
          if c == i
            errors << "node #{i} references itself"
          elsif !c.is_a?(Integer) || c.negative? || c >= nodes.size
            errors << "node #{i} has invalid child #{c}"
          end
        end
        if node["matrix"] && node["matrix"].size != 16
          errors << "node #{i}: matrix has #{node["matrix"].size} elements (expected 16)"
        end
        if node["mesh"] && !(0...(@gltf["meshes"] || []).size).cover?(node["mesh"])
          errors << "node #{i}: invalid mesh reference #{node["mesh"]}"
        end
      end
    end

    def validate_meshes(errors)
      (@gltf["meshes"] || []).each_with_index do |mesh, mi|
        (mesh["primitives"] || []).each_with_index do |prim, pi|
          pos_index = prim.dig("attributes", "POSITION")
          unless pos_index
            errors << "mesh #{mi}/#{pi}: missing POSITION attribute"
            next
          end
          position = @gltf["accessors"][pos_index]
          unless position
            errors << "mesh #{mi}/#{pi}: invalid POSITION accessor #{pos_index}"
            next
          end
          if position["min"].nil? || position["max"].nil?
            errors << "mesh #{mi}/#{pi}: POSITION accessor lacks min/max (required by spec)"
          end
          unless prim["indices"]
            errors << "mesh #{mi}/#{pi}: missing indices"
            next
          end
          index_max = accessor_data(prim["indices"]).max.to_i
          if index_max >= position["count"]
            errors << "mesh #{mi}/#{pi}: index #{index_max} out of vertex range (#{position["count"]})"
          end
          if prim["material"] && !(0...(@gltf["materials"] || []).size).cover?(prim["material"])
            errors << "mesh #{mi}/#{pi}: invalid material #{prim["material"]}"
          end
        end
      end
    end

    def validate_accessors(errors)
      views = @gltf["bufferViews"] || []
      (@gltf["accessors"] || []).each_with_index do |accessor, i|
        view = views[accessor["bufferView"]]
        unless view
          errors << "accessor #{i}: invalid bufferView"
          next
        end
        size = COMPONENT_SIZE[accessor["componentType"]]
        if size.nil?
          errors << "accessor #{i}: unsupported componentType #{accessor["componentType"]}"
          next
        end
        if accessor["byteOffset"] && accessor["byteOffset"] % size != 0
          errors << "accessor #{i}: byteOffset misaligned"
        end
        if view["byteOffset"].to_i % 4 != 0 || view["byteLength"].to_i % 4 != 0
          errors << "accessor #{i}: bufferView not 4-byte aligned"
        end
        next unless position_accessor_indices.include?(i) && accessor["min"]
        data = accessor_data(i)
        3.times do |axis|
          values = data[axis, data.size].each_slice(3).map(&:first)
          actual_min = values.min
          actual_max = values.max
          unless close?(accessor["min"][axis], actual_min) && close?(accessor["max"][axis], actual_max)
            errors << "accessor #{i}: min/max mismatch on axis #{axis} " \
                      "(declared #{accessor["min"][axis]}/#{accessor["max"][axis]}, " \
                      "actual #{actual_min}/#{actual_max})"
          end
        end
      end
    end

    def validate_buffer(errors)
      return unless @gltf["buffers"]
      total = @gltf["buffers"].sum { |b| b["byteLength"].to_i }
      unless total == @bin.bytesize
        errors << "buffer byteLength #{total} != BIN chunk size #{@bin.bytesize}"
      end
    end

    def close?(expected, actual, epsilon = 1e-5)
      (expected - actual).abs <= epsilon * [1.0, expected.abs, actual.abs].max
    end
  end
end
