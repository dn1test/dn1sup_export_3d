require "json"
path = "U:/desktop/dn1sup_export_3d/build/test_model.glb"
data = File.binread(path)
magic, ver, total = data[0, 12].unpack("VVV")
json_len, json_type = data[12, 8].unpack("VV")
json = data[20, json_len]
bin_len, bin_type = data[20 + json_len, 8].unpack("VV")
bin = data[28 + json_len, bin_len]
puts "magic=#{magic.to_s(16)} ver=#{ver} total=#{total} (file=#{data.size})"
puts "json_len=#{json_len} bin_len=#{bin_len}"
g = JSON.parse(json)
puts "nodes=#{g['nodes'].size} meshes=#{g['meshes'].size} materials=#{g['materials'].size}"
g["nodes"].first(3).each { |n| puts "node: #{n['name']} extras=#{n.dig('extras', 'sketchup').inspect}" }
g["meshes"][0]["primitives"].each { |p| puts "prim: mat=#{p['material']} idx_acc=#{p['indices']}" }
g["accessors"].each_with_index { |a, i| puts "acc#{i}: #{a['type']} count=#{a['count']} bv=#{a['bufferView']}" }
g["bufferViews"].each_with_index { |v, i| puts "bv#{i}: off=#{v['byteOffset']} len=#{v['byteLength']}" }
puts "buffer=#{g['buffers'][0]['byteLength']} bin=#{bin.size}"
bad = g["bufferViews"].any? { |v| v["byteOffset"] % 4 != 0 || v["byteLength"] % 4 != 0 }
puts "alignment ok: #{!bad}, json pad4: #{json_len % 4 == 0}, bin pad4: #{bin_len % 4 == 0}"
tri = g["accessors"].select { |a| a["type"] == "SCALAR" }.sum { |a| a["count"] / 3 }
puts "triangles: #{tri}, vertices: #{g['accessors'][0]['count']}"
