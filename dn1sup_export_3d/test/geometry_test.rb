# frozen_string_literal: true

# Geometry: coordinate system, transforms, nesting, mirrors, tricky faces.
require_relative "test_helper"

M = Dn1supTest::INCH unless defined?(M)

Dn1supTest.test("Cube: meters, Y-up, sits on the floor, 12 triangles") do
  glb = Dn1supTest.export_scene("geo_cube") do |model|
    Dn1supTest.add_cube(model.active_entities, 0, 0, 0, 10) # 10 inch cube
  end

  root = glb.gltf["nodes"][0]
  Dn1supTest.assert(root["mesh"], "root carries the loose-faces mesh")
  mesh = glb.gltf["meshes"][root["mesh"]]
  triangles = mesh["primitives"].sum { |p| glb.accessor_data(p["indices"]).size / 3 }
  Dn1supTest.assert_equal(12, triangles, "triangle count")

  min, max = Dn1supTest.node_world_bbox(glb.gltf, glb, 0)
  # (0..10)^3 inches in SketchUp: x -> x, z(up) -> y, y(depth) -> -z.
  expected_min = [0.0, 0.0, -10 * M]
  expected_max = [10 * M, 10 * M, 0.0]
  3.times do |axis|
    Dn1supTest.assert_in_delta(expected_min[axis], min[axis], 1e-5, "bbox min axis #{axis}")
    Dn1supTest.assert_in_delta(expected_max[axis], max[axis], 1e-5, "bbox max axis #{axis}")
  end
  # +Z (SketchUp up) must map to +Y (glTF up), NOT -Y.
  Dn1supTest.assert(max[1].positive?, "model occupies positive Y (up)")
end

Dn1supTest.test("Nested groups: node hierarchy with composed world transforms") do
  glb = Dn1supTest.export_scene("geo_nested") do |model|
    ents = model.active_entities
    outer = ents.add_group
    outer.transformation = Geom::Transformation.translation([100, 0, 0])
    Dn1supTest.add_cube(outer.entities, 0, 0, 0, 10)
    inner = outer.entities.add_group
    inner.transformation = Geom::Transformation.translation([0, 50, 0])
    Dn1supTest.add_cube(inner.entities, 0, 0, 0, 10)
  end

  mesh_nodes = glb.gltf["nodes"].each_index.select { |i| glb.gltf["nodes"][i]["mesh"] }
  Dn1supTest.assert(mesh_nodes.size >= 2, "expected meshes in nested groups")
  bboxes = mesh_nodes.map { |i| Dn1supTest.node_world_bbox(glb.gltf, glb, i) }

  # Both cubes share x in (100..110)in; they differ in depth (glTF z):
  # the outer group's cube sits at z in (-0.254..0), the inner one is
  # shifted by +50in of SketchUp y -> glTF z in (-1.524..-1.27).
  outer_min, outer_max = bboxes.max_by { |min, _| min[2] }
  inner_min, inner_max = bboxes.min_by { |min, _| min[2] }
  Dn1supTest.assert_in_delta(100 * M, outer_min[0], 1e-4, "outer cube world min x")
  Dn1supTest.assert_in_delta(0.0, outer_min[1], 1e-5, "outer cube world min y (on floor)")
  Dn1supTest.assert_in_delta(100 * M, inner_min[0], 1e-4, "inner cube inherits x offset")
  # inner cube: SketchUp y in (50..60)in -> glTF z in (-60*M .. -50*M)
  Dn1supTest.assert_in_delta(-60 * M, inner_min[2], 1e-4, "inner cube y offset appears as -z (min)")
  Dn1supTest.assert_in_delta(-50 * M, inner_max[2], 1e-4, "inner cube y offset appears as -z (max)")
  Dn1supTest.assert(glb.validate.empty?, "validation: #{glb.validate.join("; ")}")
end

Dn1supTest.test("Rotated component: node matrix matches conjugated rotation") do
  instance_pid = nil
  glb = Dn1supTest.export_scene("geo_rotated") do |model|
    ents = model.active_entities
    definition = model.definitions.add("rotated_cube")
    Dn1supTest.add_cube(definition.entities, 0, 0, 0, 10)
    rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 90.degrees)
    instance_pid = ents.add_instance(definition, rotation).persistent_id
  end

  node_index = Dn1supTest.find_node_by_pid(glb.gltf, instance_pid)
  Dn1supTest.assert(node_index, "instance node found by persistent_id")
  matrix = Dn1supTest.mat_from_node(glb.gltf["nodes"][node_index])
  # C * Rz(90) * C^-1 == Ry(90) in glTF space (derivation verified via probe).
  expected_flat = [0, 0, -1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1].map(&:to_f)
  actual_flat = (0...4).flat_map { |col| (0...4).map { |row| matrix[row][col] } }
  actual_flat.zip(expected_flat).each_with_index do |(actual, expected), i|
    Dn1supTest.assert_in_delta(expected, actual, 1e-6, "matrix[#{i}]")
  end

  min, max = Dn1supTest.node_world_bbox(glb.gltf, glb, node_index)
  # Rotating the (0..10)^3 cube 90 deg about Z moves it to x in (-10..0).
  Dn1supTest.assert_in_delta(-10 * M, min[0], 1e-4, "rotated bbox min x")
  Dn1supTest.assert_in_delta(0.0, max[0], 1e-4, "rotated bbox max x")
  Dn1supTest.assert_in_delta(10 * M, max[1], 1e-4, "rotated bbox max y (up)")
end

Dn1supTest.test("Mirrored component: negative determinant node matrix, mirrored bbox") do
  instance_pid = nil
  glb = Dn1supTest.export_scene("geo_mirrored") do |model|
    ents = model.active_entities
    definition = model.definitions.add("mirrored_cube")
    Dn1supTest.add_cube(definition.entities, 0, 0, 0, 10)
    mirror = Geom::Transformation.scaling(1, 1, -1) # mirror across the XY plane
    instance_pid = ents.add_instance(definition, mirror).persistent_id
  end

  node_index = Dn1supTest.find_node_by_pid(glb.gltf, instance_pid)
  Dn1supTest.assert(node_index, "instance node found")
  matrix = Dn1supTest.mat_from_node(glb.gltf["nodes"][node_index])
  Dn1supTest.assert(Dn1supTest.mat_determinant(matrix).negative?, "node matrix has negative determinant")

  min, max = Dn1supTest.node_world_bbox(glb.gltf, glb, node_index)
  # Mirror across XY sends the cube below the floor: glTF y becomes (-10..0).
  Dn1supTest.assert_in_delta(-10 * M, min[1], 1e-4, "mirrored bbox min y")
  Dn1supTest.assert_in_delta(0.0, max[1], 1e-4, "mirrored bbox max y")
end

Dn1supTest.test("Concave face: exported area equals SketchUp area") do
  area = nil
  glb = Dn1supTest.export_scene("geo_concave") do |model|
    points = [[0, 0, 0], [2, 0, 0], [2, 1, 0], [1, 1, 0], [1, 2, 0], [0, 2, 0]]
    face = model.active_entities.add_face(points.map { |a| Geom::Point3d.new(*a) })
    face.reverse! if face.normal.z.negative?
    area = face.area
  end
  root = glb.gltf["nodes"][0]
  primitives = glb.gltf["meshes"][root["mesh"]]["primitives"]
  exported_area = primitives.sum { |p| glb.triangle_area_sum(p) }
  Dn1supTest.assert_in_delta(area * M * M, exported_area, 1e-6, "triangle area sum vs face.area")
end

Dn1supTest.test("Face with a hole: hole is preserved, not filled") do
  area = nil
  glb = Dn1supTest.export_scene("geo_hole") do |model|
    ents = model.active_entities
    face = ents.add_face([[0, 0, 0], [4, 0, 0], [4, 4, 0], [0, 4, 0]].map { |a| Geom::Point3d.new(*a) })
    hole = ents.add_face([[1, 1, 0], [3, 1, 0], [3, 3, 0], [1, 3, 0]].map { |a| Geom::Point3d.new(*a) })
    hole.erase!
    face.reverse! if face.normal.z.negative?
    area = face.area
  end
  root = glb.gltf["nodes"][0]
  primitives = glb.gltf["meshes"][root["mesh"]]["primitives"]
  exported_area = primitives.sum { |p| glb.triangle_area_sum(p) }
  Dn1supTest.assert_in_delta(area * M * M, exported_area, 1e-6, "area (12 sq in) preserved")
end

Dn1supTest.test("Hidden entities and hidden layers are not exported") do
  glb = Dn1supTest.export_scene("geo_visibility") do |model|
    ents = model.active_entities
    Dn1supTest.add_cube(ents, 0, 0, 0, 10)
    hidden_group = ents.add_group
    Dn1supTest.add_cube(hidden_group.entities, 100, 0, 0, 10)
    hidden_group.visible = false
    layered = Dn1supTest.add_cube(ents, 200, 0, 0, 10)
    layer = model.layers.add("dn1_hidden_layer")
    layer.visible = false
    layered.each { |face| face.layer = layer }
  end

  _, max = Dn1supTest.node_world_bbox(glb.gltf, glb, 0)
  Dn1supTest.assert(max[0] < 99 * M, "hidden group and hidden layer excluded (max x = #{max[0].round(4)})")
  Dn1supTest.assert(glb.validate.empty?, "validation: #{glb.validate.join("; ")}")
  Dn1supTest.assert_equal(1, glb.gltf["nodes"].size, "only root node remains")
end

Dn1supTest.test("Selection scope exports only the selected entities") do
  glb = Dn1supTest.export_scene("geo_selection", scope: :selection) do |model|
    ents = model.active_entities
    Dn1supTest.add_cube(ents, 0, 0, 0, 10)
    group_b = ents.add_group
    Dn1supTest.add_cube(group_b.entities, 100, 0, 0, 10)
    selection = model.selection
    selection.clear
    selection.add(group_b)
  end
  min, = Dn1supTest.node_world_bbox(glb.gltf, glb, 0)
  Dn1supTest.assert_in_delta(100 * M, min[0], 1e-4, "only the selected group exported (min x)")
end
