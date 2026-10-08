# frozen_string_literal: true

module Dn1supExport3d
  module Exporter
    # Assembles the GLB binary chunk: a byte-accumulating buffer with 4-byte
    # alignment, plus the glTF bufferViews and accessors that address it.
    class GLBBuffer
      TARGET_ARRAY_BUFFER = 34_962
      TARGET_ELEMENT_ARRAY_BUFFER = 34_963

      COMPONENT_FLOAT = 5126
      COMPONENT_UNSIGNED_SHORT = 5123
      COMPONENT_UNSIGNED_INT = 5125

      attr_reader :views, :accessors

      def initialize
        @chunks = []
        @length = 0
        @views = []
        @accessors = []
      end

      # Appends bytes to the binary chunk (padded to 4 bytes) and returns the
      # index of the created bufferView. `target` is informational (GPU buffer
      # hint) and omitted for non-vertex data such as embedded images.
      def add_view(bytes, target: nil)
        view = { "buffer" => 0, "byteOffset" => @length, "byteLength" => bytes.bytesize }
        view["target"] = target if target
        padded = pad4(bytes)
        @chunks << padded
        @length += padded.bytesize
        @views << view
        @views.size - 1
      end

      # Registers an accessor over a range of an existing bufferView. The
      # byte_offset is relative to the bufferView start and must respect the
      # component size alignment required by the glTF spec.
      def add_accessor(view_index, component_type:, count:, type:, byte_offset: 0, min: nil, max: nil)
        accessor = {
          "bufferView" => view_index,
          "componentType" => component_type,
          "count" => count,
          "type" => type
        }
        accessor["byteOffset"] = byte_offset if byte_offset.positive?
        accessor["min"] = min if min
        accessor["max"] = max if max
        @accessors << accessor
        @accessors.size - 1
      end

      def byte_length
        @length
      end

      def to_binary
        @chunks.join
      end

      private

      def pad4(bytes)
        pad = (4 - bytes.bytesize % 4) % 4
        pad.zero? ? bytes : bytes + "\0".b * pad
      end
    end
  end
end
