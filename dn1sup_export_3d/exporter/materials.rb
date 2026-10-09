# frozen_string_literal: true

require "tempfile"
require_relative "../logger"

module Dn1supExport3d
  module Exporter
    # Converts SketchUp materials to glTF pbrMetallicRoughness materials and
    # embeds texture images into the GLB binary chunk (AGENTS.md #12/#13).
    #
    # Documented mapping decisions and fallbacks:
    # - Untextured material: color -> baseColorFactor.
    # - Textured material: the image is embedded uncolorized and
    #   baseColorFactor stays white, because SketchUp's per-material "colorize"
    #   mode is not exposed in a way we could map to glTF's factor*texture
    #   multiplication without double-tinting.
    # - opacity (alpha < 255) -> alphaMode "BLEND".
    # - SketchUp faces have separate front/back materials; a glTF primitive has
    #   one material. Only the front material is exported and the material is
    #   marked doubleSided so the back side still renders. back_material is
    #   deliberately not mapped.
    # - Core SketchUp has no roughness/metallic data: fixed neutral values
    #   (0.9 / 0.0) are used instead of invented PBR values.
    # - PNG/JPEG sources are embedded as-is; any other format (and sources
    #   that only live inside the .skp) are re-exported as PNG via
    #   Texture#write; if that fails the material falls back to solid color
    #   (reported via the shared warnings list and the Logger).
    # - embed_textures: false (lightweight preview mode) drops texture images
    #   deliberately: materials keep their base color factor.
    class MaterialConverter
      SUPPORTED_MIME = { ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg" }.freeze
      WRAP_REPEAT = 10_497

      def initialize(buffer:, warnings: nil, embed_textures: true)
        @buffer = buffer
        @warnings = warnings
        @embed_textures = embed_textures
        @cache = {}
        @list = []
        @image_cache = {}
        @images = []
        @textures = []
        @samplers = []
      end

      # Returns the glTF material index for a SketchUp material, or nil when
      # no material is assigned.
      def index(material)
        return nil unless material
        pid = material.persistent_id
        return @cache[pid] if @cache.key?(pid)
        @cache[pid] = build(material)
      end

      def to_a
        @list
      end

      def images
        @images
      end

      def textures
        @textures
      end

      def samplers
        @samplers
      end

      private

      # Adds a user-facing warning to the exporter's shared list (the dialog
      # shows it after the export) unless no collector was given.
      def warn_user(message)
        @warnings << message if @warnings
      end

      def build(material)
        r, g, b = material.color.to_a
        # Material#alpha is a 0.0..1.0 float in SketchUp 2026 (verified live);
        # Color#to_a always reports alpha 255, so it cannot be used here.
        alpha = material.alpha.to_f.clamp(0.0, 1.0)
        pbr = { "roughnessFactor" => 0.9, "metallicFactor" => 0.0 }
        # embed_textures: false (preview mode) intentionally loses the image;
        # the textured material degrades to its base color without a warning.
        texture_index = material.texture && @embed_textures ? embed_texture(material.texture) : nil
        if texture_index
          pbr["baseColorTexture"] = { "index" => texture_index }
          pbr["baseColorFactor"] = [1.0, 1.0, 1.0, alpha]
        else
          pbr["baseColorFactor"] = [r / 255.0, g / 255.0, b / 255.0, alpha]
        end
        gltf = { "name" => material.name.to_s, "pbrMetallicRoughness" => pbr, "doubleSided" => true }
        gltf["alphaMode"] = "BLEND" if alpha < 1.0
        index = @list.size
        @list << gltf
        index
      end

      def embed_texture(texture)
        return nil unless texture.valid?
        bytes, mime = texture_bytes(texture)
        unless bytes
          Logger.warn("Texture '#{texture.filename}': cannot obtain image data, falling back to solid color")
          warn_user("Текстура «#{texture.filename}» недоступна, материал показан сплошным цветом")
          return nil
        end

        key = texture.filename.to_s
        image_index = @image_cache[key]
        if image_index.nil?
          view = @buffer.add_view(bytes)
          image_index = @images.size
          @images << { "bufferView" => view, "mimeType" => mime }
          @image_cache[key] = image_index
        end

        if @samplers.empty?
          # REPEAT on both axes matches SketchUp's tiled textures (the glTF
          # default is REPEAT as well; stated explicitly for clarity).
          @samplers << { "wrapS" => WRAP_REPEAT, "wrapT" => WRAP_REPEAT }
        end
        texture_index = @textures.size
        @textures << { "sampler" => 0, "source" => image_index }
        texture_index
      end

      def texture_bytes(texture)
        path = texture.filename.to_s
        mime = SUPPORTED_MIME[File.extname(path).downcase]
        return [File.binread(path), mime] if mime && File.exist?(path)

        # The source file is missing (image embedded in the .skp) or in a
        # format browsers cannot consume: re-export the pixels as PNG.
        tmp = Tempfile.new(["dn1sup_export_3d", ".png"])
        begin
          return nil unless texture.write(tmp.path, false)
          [File.binread(tmp.path), "image/png"]
        ensure
          tmp.close
          tmp.unlink
        end
      end
    end
  end
end
