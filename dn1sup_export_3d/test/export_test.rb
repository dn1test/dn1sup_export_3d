# frozen_string_literal: true

# Export-level behaviour: empty model, exotic paths, model immutability, size.
require_relative "test_helper"

Dn1supTest.test("Empty model exports a valid minimal GLB") do
  glb = Dn1supTest.export_scene("export_empty") do |model|
    model.active_entities.clear!
  end
  errors = glb.validate
  Dn1supTest.assert(errors.empty?, "validation errors: #{errors.join("; ")}")
  Dn1supTest.assert(glb.gltf["meshes"].nil?, "no meshes key")
  Dn1supTest.assert(glb.gltf["buffers"].nil?, "no buffers key for empty binary")
  Dn1supTest.assert_equal([0], glb.gltf["scenes"][0]["nodes"])
end

Dn1supTest.test("Export works to paths with spaces and Unicode") do
  dir = File.join(Dir.tmpdir, "dn1sup_export_3d_tests", "тест папка ①")
  path = File.join(dir, "модель файл.glb")
  glb = Dn1supTest.export_scene("unicode path", path: path) do |model|
    Dn1supTest.add_cube(model.active_entities, 0, 0, 0, 10)
  end
  Dn1supTest.assert_equal(path, glb.path)
  Dn1supTest.assert(glb.validate.empty?, "exported GLB is valid")
end

Dn1supTest.test("Export does not modify the model") do
  Dn1supTest.export_scene("export_immutability") do |model|
    ents = model.active_entities
    Dn1supTest.add_cube(ents, 0, 0, 0, 10)
    group = ents.add_group
    Dn1supTest.add_cube(group.entities, 20, 0, 0, 10)

    before = Dn1supTest.snapshot(model)
    path = File.join(Dir.tmpdir, "dn1sup_export_3d_tests", "export_immutability.glb")
    Dn1supExport3d::Exporter::GLBExporter.new(model: model, scope: :all).export(path)
    after = Dn1supTest.snapshot(model)
    Dn1supTest.assert_equal(before, after, "model snapshot changed during export")
  end
end

Dn1supTest.test("100-face grid exports under 5 seconds") do
  started = nil
  path = nil
  model = Sketchup.active_model
  model.start_operation("dn1sup_export_3d test: perf grid", true)
  begin
    ents = model.active_entities
    10.times do |i|
      10.times do |j|
        ents.add_face([
          Geom::Point3d.new(i * 10, j * 10, 0),
          Geom::Point3d.new(i * 10 + 10, j * 10, 0),
          Geom::Point3d.new(i * 10 + 10, j * 10 + 10, 0),
          Geom::Point3d.new(i * 10, j * 10 + 10, 0)
        ])
      end
    end
    started = Time.now
    path = File.join(Dir.tmpdir, "dn1sup_export_3d_tests", "export_perf.glb")
    Dn1supExport3d::Exporter::GLBExporter.new(model: model, scope: :all).export(path)
    elapsed = Time.now - started
    Dn1supTest.assert(elapsed < 5.0, "export took #{elapsed.round(2)}s")
    puts "    (export took #{elapsed.round(2)}s)"
  ensure
    model.abort_operation
  end
  glb = Dn1supTest::GLBParser.parse(path)
  root = glb.gltf["nodes"][0]
  triangles = glb.gltf["meshes"][root["mesh"]]["primitives"]
                    .sum { |p| glb.accessor_data(p["indices"]).size / 3 }
  Dn1supTest.assert_equal(200, triangles, "100 quads -> 200 triangles")
end
