# frozen_string_literal: true

# Structural validation of the GLB container and the glTF graph.
require_relative "test_helper"

Dn1supTest.test("GLB container: header, chunk types, 4-byte alignment") do
  glb = Dn1supTest.export_scene("struct_container") do |model|
    Dn1supTest.add_cube(model.active_entities, 0, 0, 0, 10)
  end
  data = File.binread(glb.path)
  magic, version, total = data.unpack("a4VV")
  Dn1supTest.assert_equal("glTF", magic, "magic")
  Dn1supTest.assert_equal(2, version, "glTF version")
  Dn1supTest.assert_equal(data.bytesize, total, "header total length")

  json_len, json_type = data[12, 8].unpack("VV")
  Dn1supTest.assert_equal(Dn1supTest::GLBParser::CHUNK_JSON, json_type, "first chunk is JSON")
  Dn1supTest.assert_equal(0, json_len % 4, "JSON chunk 4-byte aligned")
  if glb.gltf["buffers"]
    bin_len, bin_type = data[20 + json_len, 8].unpack("VV")
    Dn1supTest.assert_equal(Dn1supTest::GLBParser::CHUNK_BIN, bin_type, "second chunk is BIN")
    Dn1supTest.assert_equal(0, bin_len % 4, "BIN chunk 4-byte aligned")
    Dn1supTest.assert_equal(glb.bin.bytesize, bin_len, "BIN chunk length")
  end
end

Dn1supTest.test("Node tree: valid child indices, no self references") do
  glb = Dn1supTest.export_scene("struct_nodes") do |model|
    ents = model.active_entities
    outer = ents.add_group
    Dn1supTest.add_cube(outer.entities, 0, 0, 0, 10)
    inner = outer.entities.add_group
    Dn1supTest.add_cube(inner.entities, 20, 0, 0, 10)
  end
  errors = glb.validate
  Dn1supTest.assert(errors.empty?, "validation errors: #{errors.join("; ")}")
  Dn1supTest.assert(glb.gltf["nodes"].size > 2, "expected nested nodes, got #{glb.gltf["nodes"].size}")
end

Dn1supTest.test("POSITION accessors declare min/max matching the data") do
  glb = Dn1supTest.export_scene("struct_minmax") do |model|
    Dn1supTest.add_cube(model.active_entities, 0, 0, 0, 10)
  end
  errors = glb.validate
  Dn1supTest.assert(errors.empty?, "validation errors: #{errors.join("; ")}")
end

Dn1supTest.test("Triangle winding agrees with vertex normals (CCW front faces)") do
  glb = Dn1supTest.export_scene("struct_winding") do |model|
    Dn1supTest.add_cube(model.active_entities, 0, 0, 0, 10)
  end
  glb.gltf["meshes"].each_with_index do |mesh, mi|
    mesh["primitives"].each_with_index do |prim, pi|
      Dn1supTest.assert(
        glb.winding_matches_normals?(prim),
        "mesh #{mi} primitive #{pi}: winding disagrees with normals"
      )
    end
  end
end

Dn1supTest.test("Indices stay within the vertex range of their primitive") do
  glb = Dn1supTest.export_scene("struct_indices") do |model|
    ents = model.active_entities
    Dn1supTest.add_cube(ents, 0, 0, 0, 10)
    Dn1supTest.add_cube(ents, 20, 0, 0, 10) # two cubes -> several vertex ranges
  end
  glb.gltf["meshes"].each_with_index do |mesh, mi|
    mesh["primitives"].each_with_index do |prim, pi|
      verts = glb.gltf["accessors"][prim["attributes"]["POSITION"]]["count"]
      max_index = glb.accessor_data(prim["indices"]).max
      Dn1supTest.assert(max_index < verts, "mesh #{mi}/#{pi}: index #{max_index} >= #{verts} vertices")
    end
  end
end

Dn1supTest.test("Buffer byteLength matches the BIN chunk") do
  glb = Dn1supTest.export_scene("struct_buffer") do |model|
    Dn1supTest.add_cube(model.active_entities, 0, 0, 0, 10)
  end
  declared = glb.gltf.dig("buffers", 0, "byteLength")
  Dn1supTest.assert_equal(glb.bin.bytesize, declared, "buffer byteLength")
end
