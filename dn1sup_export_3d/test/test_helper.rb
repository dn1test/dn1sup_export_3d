# frozen_string_literal: true

# Minimal test harness + fixtures for the dn1sup_export_3d test suite.
# Tests run inside SketchUp (via console_eval / ext_test): scenes are built on
# the active model inside an undo operation that is aborted afterwards, so the
# user's model is left untouched.
require "fileutils"
require_relative "../exporter/glb_exporter"
require_relative "support/glb_parser"

module Dn1supTest
  INCH = 0.0254 # inch -> meter, for expected-value math in tests

  @passed = []
  @failed = []

  class << self
    attr_reader :passed, :failed
  end

  def self.test(name)
    yield
    @passed << name
    puts "  PASS #{name}"
  rescue TestFailure => e
    @failed << [name, e.message]
    puts "  FAIL #{name}: #{e.message}"
  rescue StandardError => e
    where = e.backtrace[0, 3].join("\n    ")
    @failed << [name, "#{e.class}: #{e.message}\n    #{where}"]
    puts "  ERROR #{name}: #{e.class}: #{e.message}"
  end

  def self.report
    puts "\n=== dn1sup_export_3d: #{@passed.size} passed, #{@failed.size} failed ==="
    @failed.each do |name, message|
      puts "FAILED: #{name}\n  #{message}"
    end
    @failed.empty?
  end

  # ------------------------------------------------------------- asserts

  def self.assert(condition, message = "assertion failed")
    raise TestFailure, message unless condition
  end

  def self.assert_equal(expected, actual, message = nil)
    raise TestFailure, message || "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
  end

  def self.assert_in_delta(expected, actual, delta = 1e-4, message = nil)
    unless (expected - actual).abs <= delta
      raise TestFailure, message || "expected #{expected} +/- #{delta}, got #{actual}"
    end
  end

  # ------------------------------------------------------------- fixtures

  # Builds a throwaway scene, exports it INSIDE the undo operation (the
  # scene only exists while the operation is open) and aborts the operation
  # afterwards, leaving the user's model untouched. Pre-existing model content
  # is cleared inside the operation so tests run against a known scene.
  # Returns the parsed GLB.
  def self.export_scene(name, scope: :all, path: nil)
    model = Sketchup.active_model
    raise TestFailure, "no active model" unless model
    model.start_operation("dn1sup_export_3d test: #{name}", true)
    begin
      model.entities.clear!
      yield model
      path ||= File.join(Dir.tmpdir, "dn1sup_export_3d_tests", "#{name}.glb")
      FileUtils.mkdir_p(File.dirname(path))
      Dn1supExport3d::Exporter::GLBExporter.new(model: model, scope: scope).export(path)
    ensure
      model.abort_operation
    end
    GLBParser.parse(path)
  end

  # Adds an axis-aligned cube with outward-facing normals; returns its faces.
  def self.add_cube(entities, x, y, z, size)
    p = ->(a, b, c) { Geom::Point3d.new(a, b, c) }
    sides = {
      [0, 0, -1] => [[x, y, z], [x + size, y, z], [x + size, y + size, z], [x, y + size, z]],
      [0, 0, 1] => [[x, y, z + size], [x + size, y, z + size], [x + size, y + size, z + size], [x, y + size, z + size]],
      [0, -1, 0] => [[x, y, z], [x + size, y, z], [x + size, y, z + size], [x, y, z + size]],
      [0, 1, 0] => [[x, y + size, z], [x + size, y + size, z], [x + size, y + size, z + size], [x, y + size, z + size]],
      [-1, 0, 0] => [[x, y, z], [x, y + size, z], [x, y + size, z + size], [x, y, z + size]],
      [1, 0, 0] => [[x + size, y, z], [x + size, y + size, z], [x + size, y + size, z + size], [x + size, y, z + size]]
    }
    sides.map do |normal, points|
      face = entities.add_face(points.map { |a| p.call(*a) })
      face.reverse! if face.normal.dot(Geom::Vector3d.new(*normal)) < 0
      face
    end
  end

  # Writes a valid 2x2 RGBA PNG (no SketchUp API needed).
  def self.write_png(path, width = 2, height = 2)
    require "zlib"
    rows = Array.new(height) do
      [0].concat(Array.new(width * 4, 255)).pack("C*") # filter 0, opaque white
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
    path
  end

  # ------------------------------------------------------ matrix helpers

  # All glTF matrices here are row-major nested arrays.

  def self.mat_identity
    [[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, 1.0]]
  end

  def self.mat_mul(a, b)
    (0...4).map { |i| (0...4).map { |j| (0...4).sum { |k| a[i][k] * b[k][j] } } }
  end

  def self.mat_determinant(m)
    m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
      m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
      m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
  end

  # glTF node "matrix" (column-major flat) -> row-major nested.
  def self.mat_from_node(node)
    return mat_identity unless node && node["matrix"]
    flat = node["matrix"]
    (0...4).map { |row| (0...4).map { |col| flat[col * 4 + row] } }
  end

  # World (root->node) matrix for every node, keyed by node index.
  def self.world_matrices(gltf)
    worlds = {}
    walk = lambda do |index, parent|
      node = gltf["nodes"][index]
      world = parent ? mat_mul(parent, mat_from_node(node)) : mat_from_node(node)
      worlds[index] = world
      (node["children"] || []).each { |child| walk.call(child, world) }
    end
    scene = gltf["scenes"][gltf["scene"] || 0]
    (scene ? scene["nodes"] : []).each { |n| walk.call(n, nil) }
    worlds
  end

  def self.mat_transform(m, v)
    x, y, z = v
    [
      m[0][0] * x + m[0][1] * y + m[0][2] * z + m[0][3],
      m[1][0] * x + m[1][1] * y + m[1][2] * z + m[1][3],
      m[2][0] * x + m[2][1] * y + m[2][2] * z + m[2][3]
    ]
  end

  # World-space bbox [min, max] of the mesh carried by a node. For mesh-less
  # nodes (component instances) the union over all mesh-carrying descendants
  # is returned. Computed from the POSITION accessors' declared min/max,
  # transformed by the world matrix.
  def self.node_world_bbox(gltf, parser, node_index)
    node = gltf["nodes"][node_index]
    world = world_matrices(gltf)[node_index]
    unless node["mesh"]
      boxes = (node["children"] || []).filter_map { |child| node_world_bbox(gltf, parser, child) }
      return nil if boxes.empty?
      return [
        3.times.map { |axis| boxes.map { |min, _| min[axis] }.min },
        3.times.map { |axis| boxes.map { |_, max| max[axis] }.max }
      ]
    end
    mesh = gltf["meshes"][node["mesh"]]
    mins = nil
    maxs = nil
    mesh["primitives"].each do |prim|
      accessor = gltf["accessors"][prim["attributes"]["POSITION"]]
      mins = accessor["min"].dup if mins.nil?
      maxs = accessor["max"].dup if maxs.nil?
      3.times do |axis|
        mins[axis] = [mins[axis], accessor["min"][axis]].min
        maxs[axis] = [maxs[axis], accessor["max"][axis]].max
      end
    end
    corners = [mins[0], maxs[0]].product([mins[1], maxs[1]], [mins[2], maxs[2]])
    world_corners = corners.map { |c| mat_transform(world, c) }
    [
      3.times.map { |axis| world_corners.map { |c| c[axis] }.min },
      3.times.map { |axis| world_corners.map { |c| c[axis] }.max }
    ]
  end

  # Finds the first node whose extras.sketchup.persistent_id matches.
  def self.find_node_by_pid(gltf, pid)
    gltf["nodes"].each_with_index do |node, index|
      next unless node.is_a?(Hash)
      skp = node.dig("extras", "sketchup")
      return index if skp && skp["persistent_id"].to_s == pid.to_s
    end
    nil
  end

  # Comparable snapshot of the parts of the model an export must not touch.
  def self.snapshot(model)
    {
      entities: model.entities.count,
      materials: model.materials.count,
      layers: model.layers.count,
      definitions: model.definitions.count,
      bounds: [model.bounds.min.to_a.map(&:to_f), model.bounds.max.to_a.map(&:to_f)]
    }
  end
end
