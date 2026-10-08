# frozen_string_literal: true

# Object structure: definitions/instances, metadata identity, node reuse.
require_relative "test_helper"

Dn1supTest.test("Component definition instanced twice shares one mesh") do
  pids = nil
  glb = Dn1supTest.export_scene("struct_instances") do |model|
    ents = model.active_entities
    definition = model.definitions.add("shared_cube")
    Dn1supTest.add_cube(definition.entities, 0, 0, 0, 10)
    first = ents.add_instance(definition, Geom::Transformation.translation([0, 0, 0]))
    second = ents.add_instance(definition, Geom::Transformation.translation([100, 0, 0]))
    pids = [first.persistent_id, second.persistent_id]
  end

  instance_nodes = pids.map { |pid| Dn1supTest.find_node_by_pid(glb.gltf, pid) }
  Dn1supTest.assert(instance_nodes.all?, "both instance nodes found")
  mesh_indices = instance_nodes.map do |index|
    child = glb.gltf["nodes"][index]["children"][0]
    glb.gltf["nodes"][child]["mesh"]
  end
  Dn1supTest.assert_equal(1, glb.gltf["meshes"].size, "exactly one mesh in the file")
  Dn1supTest.assert_equal(mesh_indices[0], mesh_indices[1], "instances share the same mesh index")

  min1, = Dn1supTest.node_world_bbox(glb.gltf, glb, instance_nodes[0])
  min2, = Dn1supTest.node_world_bbox(glb.gltf, glb, instance_nodes[1])
  Dn1supTest.assert_in_delta(0.0, min1[0], 1e-5, "instance 1 at origin")
  Dn1supTest.assert_in_delta(100 * 0.0254, min2[0], 1e-4, "instance 2 translated 100in")
end

Dn1supTest.test("Instance nodes carry distinct persistent_ids, children reference the definition") do
  definition_pid = nil
  pids = nil
  glb = Dn1supTest.export_scene("struct_metadata") do |model|
    ents = model.active_entities
    definition = model.definitions.add("meta_cube")
    Dn1supTest.add_cube(definition.entities, 0, 0, 0, 10)
    first = ents.add_instance(definition, Geom::Transformation.new)
    second = ents.add_instance(definition, Geom::Transformation.translation([50, 0, 0]))
    definition_pid = definition.persistent_id
    pids = [first.persistent_id, second.persistent_id]
  end

  exported_pids = pids.map do |pid|
    index = Dn1supTest.find_node_by_pid(glb.gltf, pid)
    Dn1supTest.assert(index, "instance node #{pid} present")
    node = glb.gltf["nodes"][index]
    skp = node.dig("extras", "sketchup")
    Dn1supTest.assert_equal("ComponentInstance", skp["entity_type"])
    child = glb.gltf["nodes"][node["children"][0]]
    child_skp = child.dig("extras", "sketchup")
    Dn1supTest.assert_equal(definition_pid, child_skp["persistent_id"],
                            "child references the definition, not the instance")
    skp["persistent_id"]
  end
  Dn1supTest.assert(exported_pids.uniq.size == 2, "instance persistent_ids are distinct: #{exported_pids.inspect}")
end

Dn1supTest.test("Group nodes expose name and layer in extras") do
  group_pid = nil
  glb = Dn1supTest.export_scene("struct_group_meta") do |model|
    group = model.active_entities.add_group
    group.name = "Cabinet"
    Dn1supTest.add_cube(group.entities, 0, 0, 0, 10)
    group_pid = group.persistent_id
  end
  node_index = Dn1supTest.find_node_by_pid(glb.gltf, group_pid)
  Dn1supTest.assert(node_index, "group node found")
  node = glb.gltf["nodes"][node_index]
  skp = node.dig("extras", "sketchup")
  Dn1supTest.assert_equal("Cabinet", skp["name"])
  Dn1supTest.assert_equal("Group", skp["entity_type"])
  Dn1supTest.assert_equal("Layer0", skp["layer"])
  Dn1supTest.assert_equal("Cabinet", node["name"])
end

Dn1supTest.test("Empty groups produce no nodes") do
  glb = Dn1supTest.export_scene("struct_empty_group") do |model|
    model.active_entities.add_group
  end
  Dn1supTest.assert_equal(1, glb.gltf["nodes"].size, "only the root node")
  Dn1supTest.assert_equal([0], glb.gltf["scenes"][0]["nodes"])
end
