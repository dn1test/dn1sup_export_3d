# frozen_string_literal: true

# Materials: colors, alpha, textures, UVs.
require_relative "test_helper"

Dn1supTest.test("Solid color becomes baseColorFactor, doubleSided") do
  glb = Dn1supTest.export_scene("mat_solid") do |model|
    face = model.active_entities.add_face(
      [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0), Geom::Point3d.new(10, 10, 0), Geom::Point3d.new(0, 10, 0)]
    )
    material = model.materials.add("red")
    material.color = Sketchup::Color.new(200, 30, 40)
    face.material = material
  end
  material = glb.gltf["materials"][0]
  Dn1supTest.assert_equal("red", material["name"])
  factor = material.dig("pbrMetallicRoughness", "baseColorFactor")
  Dn1supTest.assert_in_delta(200 / 255.0, factor[0], 1e-5, "red channel")
  Dn1supTest.assert_in_delta(30 / 255.0, factor[1], 1e-5, "green channel")
  Dn1supTest.assert_in_delta(40 / 255.0, factor[2], 1e-5, "blue channel")
  Dn1supTest.assert_in_delta(1.0, factor[3], 1e-5, "alpha")
  Dn1supTest.assert_equal(true, material["doubleSided"], "doubleSided fallback for two-sided faces")
  Dn1supTest.assert(material["alphaMode"].nil?, "opaque material has no alphaMode")
end

Dn1supTest.test("Material alpha becomes alphaMode BLEND") do
  glb = Dn1supTest.export_scene("mat_alpha") do |model|
    face = model.active_entities.add_face(
      [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0), Geom::Point3d.new(10, 10, 0), Geom::Point3d.new(0, 10, 0)]
    )
    material = model.materials.add("glassy")
    material.color = Sketchup::Color.new(100, 150, 200)
    material.alpha = 0.5 # Material#alpha is a 0.0..1.0 float in SketchUp 2026
    face.material = material
  end
  material = glb.gltf["materials"][0]
  Dn1supTest.assert_equal("BLEND", material["alphaMode"])
  factor = material.dig("pbrMetallicRoughness", "baseColorFactor")
  Dn1supTest.assert_in_delta(0.5, factor[3], 1e-5, "alpha channel")
end

PNG_FIXTURE = File.join(Dir.tmpdir, "dn1sup_export_3d_tests", "fixture.png")

Dn1supTest.write_png(PNG_FIXTURE)

Dn1supTest.test("Texture image is embedded and wired to the material") do
  glb = Dn1supTest.export_scene("mat_texture") do |model|
    face = model.active_entities.add_face(
      [Geom::Point3d.new(10, 0, 0), Geom::Point3d.new(11, 0, 0), Geom::Point3d.new(11, 1, 0), Geom::Point3d.new(10, 1, 0)]
    )
    face.reverse! if face.normal.z.negative?
    material = model.materials.add("textured")
    material.texture = PNG_FIXTURE
    face.material = material
  end

  image = glb.gltf["images"][0]
  Dn1supTest.assert(image, "image present")
  Dn1supTest.assert_equal("image/png", image["mimeType"])
  view = glb.gltf["bufferViews"][image["bufferView"]]
  bytes = glb.bin[view["byteOffset"], view["byteLength"]]
  Dn1supTest.assert(bytes.start_with?("\x89PNG".b), "embedded bytes are a PNG")

  texture = glb.gltf["textures"][0]
  Dn1supTest.assert_equal(0, texture["source"], "texture.source points at the image")
  material = glb.gltf["materials"][0]
  Dn1supTest.assert_equal(0, material.dig("pbrMetallicRoughness", "baseColorTexture", "index"))
  Dn1supTest.assert(glb.gltf["samplers"], "sampler present")
  Dn1supTest.assert_equal(true, material["doubleSided"])
end

Dn1supTest.test("UVs are exported with glTF V direction (flip vs SketchUp)") do
  glb = Dn1supTest.export_scene("mat_uv") do |model|
    face = model.active_entities.add_face(
      [Geom::Point3d.new(10, 0, 0), Geom::Point3d.new(11, 0, 0), Geom::Point3d.new(11, 1, 0), Geom::Point3d.new(10, 1, 0)]
    )
    face.reverse! if face.normal.z.negative?
    material = model.materials.add("textured")
    material.texture = PNG_FIXTURE
    face.material = material
  end
  primitive = glb.gltf["meshes"][0]["primitives"][0]
  positions = glb.accessor_data(primitive["attributes"]["POSITION"])
  uvs = glb.accessor_data(primitive["attributes"]["TEXCOORD_0"])
  Dn1supTest.assert(!uvs.empty?, "TEXCOORD_0 data present")

  vertices = (0...(positions.size / 3)).map do |i|
    { x: positions[i * 3], y: positions[i * 3 + 1], z: positions[i * 3 + 2], u: uvs[i * 2], v: uvs[i * 2 + 1] }
  end
  # This face is horizontal in SketchUp, so its SketchUp +Y (depth) becomes
  # glTF -Z. SketchUp V grows with +Y; glTF V must grow the opposite way, so
  # the vertex with the LARGEST glTF z (SketchUp y=0, the texture's bottom
  # edge) must carry the LARGEST v.
  su_bottom = vertices.max_by { |vertex| vertex[:z] }
  su_top = vertices.min_by { |vertex| vertex[:z] }
  Dn1supTest.assert(su_bottom[:v] > su_top[:v],
                    "V flipped: bottom v=#{su_bottom[:v].round(4)} must exceed top v=#{su_top[:v].round(4)}")
  # u grows with glTF x; both ranges span 1 inch of a 10-inch texture.
  us = vertices.map { |vertex| vertex[:u] }
  vs = vertices.map { |vertex| vertex[:v] }
  Dn1supTest.assert_in_delta(0.1, us.max - us.min, 1e-3, "u range (1in of 10in texture)")
  Dn1supTest.assert_in_delta(0.1, vs.max - vs.min, 1e-3, "v range")
end

Dn1supTest.test("Faces with different materials become separate primitives") do
  glb = Dn1supTest.export_scene("mat_multi") do |model|
    ents = model.active_entities
    red = ents.add_face([Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0), Geom::Point3d.new(10, 10, 0)])
    red_material = model.materials.add("red")
    red_material.color = Sketchup::Color.new(255, 0, 0)
    red.material = red_material
    blue = ents.add_face([Geom::Point3d.new(20, 0, 0), Geom::Point3d.new(30, 0, 0), Geom::Point3d.new(30, 10, 0)])
    blue_material = model.materials.add("blue")
    blue_material.color = Sketchup::Color.new(0, 0, 255)
    blue.material = blue_material
  end
  root = glb.gltf["nodes"][0]
  primitives = glb.gltf["meshes"][root["mesh"]]["primitives"]
  Dn1supTest.assert_equal(2, primitives.size, "one primitive per material")
  materials = primitives.map { |p| p["material"] }
  Dn1supTest.assert_equal(materials.compact.sort, materials.compact.uniq, "distinct materials per primitive")
end
