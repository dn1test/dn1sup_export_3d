# materials.rb
module Dn1supExport3d
  module Exporter
    class MaterialConverter
      def initialize
        @cache = {}
        @list = []
      end

      def index(material)
        return nil unless material
        cached = @cache[material.persistent_id]
        return cached if cached

        r, g, b, a = material.color.to_a.map { |v| v / 255.0 }
        gltf = {
          "name" => material.name,
          "pbrMetallicRoughness" => {
            "baseColorFactor" => [r, g, b, 1.0],
            "roughnessFactor" => 0.9,
            "metallicFactor" => 0.0
          }
        }
        if a < 1.0
          gltf["alphaMode"] = "BLEND"
          gltf["pbrMetallicRoughness"]["baseColorFactor"] = [r, g, b, a]
        end
        idx = @list.size
        @list << gltf
        @cache[material.persistent_id] = idx
        idx
      end

      def to_a
        @list
      end
    end
  end
end
