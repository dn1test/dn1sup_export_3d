# frozen_string_literal: true

# Standalone GLB sanity dumper/validator. Plain Ruby, no SketchUp required:
#
#   ruby build/check_glb.rb path/to/model.glb
#
# Prints container/chunk info, scene summary and structural validation
# errors (empty list = valid).
require_relative "../dn1sup_export_3d/test/support/glb_parser"

path = ARGV[0] || File.join(__dir__, "test_model.glb")
glb = Dn1supTest::GLBParser.parse(path)
gltf = glb.gltf

data = File.binread(path)
magic, version, total = data.unpack("a4VV")
json_len = data[12, 8].unpack("VV")[0]

puts "File:          #{path} (#{data.bytesize} bytes)"
puts "GLB:           magic=#{magic.inspect} version=#{version} header total=#{total}"
puts "Chunks:        JSON #{json_len} B" + (gltf["buffers"] ? " + BIN #{glb.bin.bytesize} B" : "")
puts
puts "Scenes:        #{gltf["scenes"]&.size} (active: #{gltf["scene"] || 0})"
puts "Nodes:         #{gltf["nodes"]&.size}"
puts "Meshes:        #{gltf["meshes"]&.size}"
puts "Materials:     #{gltf["materials"]&.size}"
puts "Textures:      #{gltf["textures"]&.size}"
puts "Images:        #{gltf["images"]&.size}"

triangles = (gltf["meshes"] || []).sum do |mesh|
  mesh["primitives"].sum { |prim| glb.accessor_data(prim["indices"]).size / 3 }
rescue Dn1supTest::TestFailure
  0
end
puts "Triangles:     #{triangles}"

if gltf["nodes"]
  puts
  puts "Node extras (first 10):"
  gltf["nodes"].first(10).each do |node|
    skp = node.is_a?(Hash) && node.dig("extras", "sketchup")
    next unless skp
    puts "  - #{node["name"]}: #{skp["entity_type"]} pid=#{skp["persistent_id"]} layer=#{skp["layer"].inspect}"
  end
end

errors = glb.validate
puts
if errors.empty?
  puts "Validation:    OK (no structural errors)"
else
  puts "Validation:    #{errors.size} error(s):"
  errors.each { |error| puts "  - #{error}" }
  exit 1
end
