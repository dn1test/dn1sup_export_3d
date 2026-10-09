# frozen_string_literal: true

# Stepwise export API (begin/step/finish) used by the export dialog for
# progress + cancellation: byte-identical output, in-memory GLB, progress
# accounting, texture embedding toggle.
require_relative "test_helper"

# Cube + named group + component definition with two instances + a face at
# the model root: every node kind the traversal can meet.
def dn1sup_stepwise_fixture(model)
  ents = model.active_entities
  Dn1supTest.add_cube(ents, 0, 0, 0, 10)
  group = ents.add_group
  group.name = "StepGroup"
  Dn1supTest.add_cube(group.entities, 20, 0, 0, 10)
  definition = model.definitions.add("StepComp")
  Dn1supTest.add_cube(definition.entities, 0, 0, 0, 5)
  ents.add_instance(definition, Geom::Transformation.new([40, 0, 0]))
  ents.add_instance(definition, Geom::Transformation.new([50, 0, 0]))
end

Dn1supTest.test("Stepwise export is byte-identical to one-call export") do
  model = Sketchup.active_model
  dir = File.join(Dir.tmpdir, "dn1sup_export_3d_tests")
  path_a = File.join(dir, "stepwise_direct.glb")
  path_b = File.join(dir, "stepwise_stepped.glb")
  model.start_operation("dn1sup_export_3d test: stepwise parity", true)
  begin
    model.entities.clear!
    dn1sup_stepwise_fixture(model)
    Dn1supExport3d::Exporter::GLBExporter.new(model: model, scope: :all).export(path_a)

    exporter = Dn1supExport3d::Exporter::GLBExporter.new(model: model, scope: :all)
    exporter.begin_export
    # step(0) processes exactly one container per call: worst-case granularity.
    exporter.step(0) until exporter.done?
    File.binwrite(path_b, exporter.finish)
  ensure
    model.abort_operation
  end
  Dn1supTest.assert_equal(File.binread(path_a), File.binread(path_b), "GLB bytes differ between stepwise and one-call export")
end

Dn1supTest.test("finish returns a valid in-memory GLB with summary stats") do
  binary = nil
  model = Sketchup.active_model
  model.start_operation("dn1sup_export_3d test: stepwise finish", true)
  begin
    model.entities.clear!
    dn1sup_stepwise_fixture(model)
    exporter = Dn1supExport3d::Exporter::GLBExporter.new(model: model, scope: :all)
    exporter.begin_export
    exporter.step(0.01) until exporter.done?
    binary = exporter.finish
    Dn1supTest.assert_equal({ faces: 18, triangles: 36, meshes: 3, materials: 0, textures: 0 },
                            exporter.summary, "summary counters")
    Dn1supTest.assert(exporter.elapsed.is_a?(Numeric), "elapsed numeric")
    Dn1supTest.assert(exporter.warnings.empty?, "no warnings on a clean scene")
  ensure
    model.abort_operation
  end
  path = File.join(Dir.tmpdir, "dn1sup_export_3d_tests", "stepwise_finish.glb")
  File.binwrite(path, binary)
  glb = Dn1supTest::GLBParser.parse(path)
  Dn1supTest.assert(glb.validate.empty?, "in-memory GLB is valid: #{glb.validate.join('; ')}")
  Dn1supTest.assert_equal(3, glb.gltf["meshes"].size, "mesh count in GLB")
end

Dn1supTest.test("progress reports container counts and current name") do
  model = Sketchup.active_model
  model.start_operation("dn1sup_export_3d test: stepwise progress", true)
  begin
    model.entities.clear!
    dn1sup_stepwise_fixture(model)
    exporter = Dn1supExport3d::Exporter::GLBExporter.new(model: model, scope: :all)
    exporter.begin_export
    Dn1supTest.assert_equal({ done: 0, total: 3, current: nil }, exporter.progress, "initial progress")

    exporter.step(0)
    first = exporter.progress
    Dn1supTest.assert_equal(1, first[:done], "one container after step(0)")
    Dn1supTest.assert(first[:current].is_a?(String) && !first[:current].empty?, "current name reported while pending")

    exporter.step(5) until exporter.done?
    Dn1supTest.assert_equal({ done: 3, total: 3, current: nil }, exporter.progress, "final progress")
  ensure
    model.abort_operation
  end
end

Dn1supTest.test("embed_textures: false drops images but keeps material colors") do
  png = Dn1supTest.write_png(File.join(Dir.tmpdir, "dn1sup_export_3d_tests", "stepwise_tex.png"))
  glb = Dn1supTest.export_scene("stepwise_no_textures", embed_textures: false) do |model|
    material = model.materials.add("StepTexMat")
    material.texture = png
    face = Dn1supTest.add_cube(model.active_entities, 0, 0, 0, 10)[0]
    face.material = material
  end
  Dn1supTest.assert(glb.gltf["images"].nil?, "no images without embed_textures")
  Dn1supTest.assert(glb.gltf["textures"].nil?, "no textures without embed_textures")
  pbr = glb.gltf["materials"][0]["pbrMetallicRoughness"]
  Dn1supTest.assert(pbr["baseColorTexture"].nil?, "no baseColorTexture without embed_textures")
  Dn1supTest.assert_equal([1.0, 1.0, 1.0, 1.0], pbr["baseColorFactor"], "white base color factor (texture source is white)")

  glb = Dn1supTest.export_scene("stepwise_no_textures") do |model|
    material = model.materials.add("StepTexMat")
    material.texture = png
    face = Dn1supTest.add_cube(model.active_entities, 0, 0, 0, 10)[0]
    face.material = material
  end
  Dn1supTest.assert_equal(1, Dn1supTest.last_stats[:textures], "texture embedded by default")
end
