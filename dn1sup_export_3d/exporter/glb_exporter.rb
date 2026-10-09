# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../logger"
require_relative "../version"
require_relative "coordinate"
require_relative "buffer"
require_relative "materials"
require_relative "geometry"

module Dn1supExport3d
  module Exporter
    # Exports a SketchUp model (or the current selection) to a binary glTF 2.0
    # file (GLB). The model is only read, never modified (AGENTS.md #7).
    #
    # Structure: the glTF node tree mirrors the SketchUp object tree. Geometry
    # of each container (model root, group, component definition) is stored in
    # the container's local coordinate system; instance transformations live
    # on the nodes. Component definitions are exported once and their node
    # subtree is cloned per instance, so instances share mesh data without
    # duplicating geometry. Every instance node carries extras.sketchup
    # metadata (persistent_id / entity_type / name / layer) so the web viewer
    # can map clicks back to SketchUp objects (AGENTS.md #14/#15).
    #
    # Visibility (documented rules, AGENTS.md #17): hidden entities and
    # entities on hidden tags/layers are skipped at every level unless
    # include_hidden: true is set (export dialog option). Page-specific
    # visibility overrides and "hide rest of model" are not applied.
    #
    # The export can run stepwise so a UI can drive it from a timer and stay
    # responsive (progress + cancellation, AGENTS.md #26):
    #
    #   exporter.begin_export
    #   exporter.step(0.15) until exporter.done?
    #   glb_binary = exporter.finish
    #
    # #export(path) is the one-call equivalent and produces byte-identical
    # output. Root containers deleted between steps (the user may edit the
    # model mid-export) are skipped via Entity#valid?.
    class GLBExporter
      MAGIC = 0x46546C67        # "glTF"
      GLB_VERSION = 2
      CHUNK_JSON = 0x4E4F534A   # "JSON"
      CHUNK_BIN = 0x004E4942    # "BIN\0"

      SCOPES = [:all, :selection].freeze

      # User-facing warnings collected during the export (texture failures,
      # circular component references); also mirrored to the Logger.
      attr_reader :warnings

      def initialize(model:, scope: :all, include_hidden: false, embed_textures: true)
        unless SCOPES.include?(scope)
          raise ArgumentError, "Unknown scope #{scope.inspect} (expected one of #{SCOPES.join(', ')})"
        end
        @model = model
        @scope = scope
        @include_hidden = include_hidden
        @embed_textures = embed_textures
        @warnings = []
      end

      # Phase 1: snapshot the scope and prepare the shared caches. Root faces
      # are meshed immediately (they have no progress weight of their own);
      # root containers go into the step queue.
      def begin_export
        @started = Time.now
        @materials = MaterialConverter.new(
          buffer: @buffer = GLBBuffer.new,
          warnings: @warnings,
          embed_textures: @embed_textures
        )
        @meshes = []
        @definition_templates = {}
        @definition_stack = []
        @root_children = []

        roots = @scope == :selection ? @model.selection.to_a : @model.entities.to_a
        @root_mesh = MeshData.new(@materials)
        roots.each { |e| @root_mesh.add_face(e) if e.is_a?(Sketchup::Face) && visible?(e) }
        @pending = roots.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        @total_containers = @pending.size
        @current_name = nil
        nil
      end

      # Phase 2: processes pending root containers for up to `seconds` of wall
      # time (always at least one, so step(0) advances by a single container).
      # Returns true when the queue is drained.
      def step(seconds = 0.15)
        deadline = Time.now + seconds
        until @pending.empty?
          entity = @pending.shift
          if entity.valid? && visible?(entity)
            @current_name = display_name(entity)
            node = entity_node(entity)
            @root_children << node if node
          end
          break if Time.now >= deadline
        end
        @current_name = nil if @pending.empty?
        done?
      end

      def done?
        @pending.empty?
      end

      # {done:, total:, current:} for progress reporting; current is the
      # display name of the container being processed (or nil between steps).
      def progress
        { done: @total_containers - @pending.size, total: @total_containers, current: @current_name }
      end

      # Phase 3: assembles the glTF scene and returns the GLB binary. The
      # caller writes it where it is needed (file, in-memory preview, ...).
      def finish
        root = { "name" => root_name }
        root["mesh"] = register_mesh(@root_mesh) unless @root_mesh.empty?
        root["children"] = @root_children unless @root_children.empty?
        glb_string(assemble_gltf(root))
      end

      def elapsed
        (Time.now - @started).round(2)
      end

      # Geometry/material counters of the finished export (valid after #finish).
      def summary
        {
          faces: @meshes.sum(&:face_count),
          triangles: @meshes.sum(&:triangle_count),
          meshes: @meshes.size,
          materials: @materials.to_a.size,
          textures: @materials.images.size
        }
      end

      # One-call export. Returns a stats hash (path, faces, triangles, meshes,
      # materials, textures, bytes, seconds) describing the written file.
      def export(path)
        begin_export
        step until done?
        glb = finish
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, glb)

        stats = build_stats(path, glb)
        Logger.info(
          "Exported #{stats[:faces]} faces (#{stats[:triangles]} triangles, " \
          "#{stats[:meshes]} meshes, #{stats[:materials]} materials, " \
          "#{stats[:textures]} textures) to #{path} in #{stats[:seconds]}s"
        )
        stats
      end

      private

      def build_stats(path, glb)
        { path: path, **summary, bytes: glb.bytesize, seconds: elapsed }
      end

      def root_name
        title = @model.title.to_s
        return "Selection" if @scope == :selection
        title.empty? ? "SketchUp Model" : title
      end

      # ------------------------------------------------------- entity nodes

      def entity_node(entity)
        return nil unless visible?(entity)
        case entity
        when Sketchup::Group
          group_node(entity)
        when Sketchup::ComponentInstance
          instance_node(entity)
        end
      end

      def group_node(group)
        inner = group.entities
        mesh = container_mesh(inner)
        children = inner.filter_map { |e| entity_node(e) }
        return nil if mesh.empty? && children.empty?

        node = base_node(group)
        node["mesh"] = register_mesh(mesh) unless mesh.empty?
        node["children"] = children unless children.empty?
        node
      end

      # A component instance references the (memoized) node subtree of its
      # definition. The subtree is deep-copied per instance so the same
      # meshes are shared without duplicating geometry.
      def instance_node(instance)
        template = definition_template(instance.definition)
        return nil if template.empty?

        node = base_node(instance)
        node["children"] = template.map { |child| deep_dup_node(child) }
        node
      end

      def base_node(entity)
        node = { "name" => display_name(entity) }
        node["matrix"] = Coordinate.matrix4(entity.transformation) unless entity.transformation.identity?
        node["extras"] = { "sketchup" => metadata(entity) }
        node
      end

      def metadata(entity)
        {
          "persistent_id" => entity.persistent_id,
          "entity_type" => entity.class.name.split("::").last,   # Group | ComponentInstance | ComponentDefinition
          "name" => entity.name.to_s,
          "layer" => (entity.layer.name.to_s if entity.layer.respond_to?(:name))
        }.compact
      end

      def display_name(entity)
        name = entity.name.to_s
        return name unless name.empty?
        entity.is_a?(Sketchup::Group) ? "Group" : entity.definition.name.to_s
      end

      # Faces that live directly in a container (not inside a nested
      # group/instance) become that container's mesh.
      def container_mesh(entities)
        mesh = MeshData.new(@materials)
        entities.each { |e| mesh.add_face(e) if e.is_a?(Sketchup::Face) && visible?(e) }
        mesh
      end

      def definition_template(definition)
        pid = definition.persistent_id
        return @definition_templates[pid] if @definition_templates.key?(pid)
        if @definition_stack.include?(pid)
          Logger.warn("Circular component reference at definition '#{definition.name}' (#{pid}); nested instance skipped")
          @warnings << "Компонент «#{definition.name}»: циклическая ссылка, вложенный экземпляр пропущен"
          return []
        end

        @definition_stack << pid
        begin
          nodes = []
          mesh = container_mesh(definition.entities)
          unless mesh.empty?
            nodes << {
              "name" => definition.name.to_s,
              "mesh" => register_mesh(mesh),
              "extras" => {
                "sketchup" => {
                  "persistent_id" => pid,
                  "entity_type" => "ComponentDefinition",
                  "name" => definition.name.to_s
                }
              }
            }
          end
          nodes.concat(definition.entities.filter_map { |e| entity_node(e) })
          nodes
        ensure
          @definition_stack.pop
        end.tap { |nodes| @definition_templates[pid] = nodes }
      end

      def register_mesh(mesh)
        @meshes << mesh
        @meshes.size - 1
      end

      def visible?(entity)
        return true if @include_hidden
        return false unless entity.visible?
        layer = entity.layer
        layer.nil? || layer.visible?
      end

      # ----------------------------------------------------------- assembly

      def assemble_gltf(root)
        gltf = {
          "asset" => { "version" => "2.0", "generator" => "dn1sup_export_3d #{Dn1supExport3d::VERSION}" },
          "scene" => 0,
          "scenes" => [{ "nodes" => [0] }],
          "nodes" => flatten_nodes(root)
        }
        meshes = @meshes.map { |m| m.build_mesh(@buffer) }
        gltf["meshes"] = meshes unless meshes.empty?
        gltf["materials"] = @materials.to_a unless @materials.to_a.empty?
        gltf["textures"] = @materials.textures unless @materials.textures.empty?
        gltf["images"] = @materials.images unless @materials.images.empty?
        gltf["samplers"] = @materials.samplers unless @materials.samplers.empty?
        gltf["accessors"] = @buffer.accessors unless @buffer.accessors.empty?
        gltf["bufferViews"] = @buffer.views unless @buffer.views.empty?
        gltf["buffers"] = [{ "byteLength" => @buffer.byte_length }] if @buffer.byte_length.positive?
        gltf
      end

      # Converts a node hash tree into the flat glTF nodes array. Children are
      # appended depth-first after their parent, so every child index is
      # valid and greater than its parent's index (no self-references).
      def flatten_nodes(root)
        nodes = []
        walk = lambda do |node|
          index = nodes.size
          nodes << nil
          node["children"] = node["children"].map { |child| walk.call(child) } if node["children"]
          nodes[index] = node
          index
        end
        walk.call(root)
        nodes
      end

      def deep_dup_node(node)
        duped = node.dup
        duped["children"] = node["children"].map { |child| deep_dup_node(child) } if node["children"]
        duped
      end

      # -------------------------------------------------------------- GLB

      # GLB container: 12-byte header, JSON chunk (4-byte padded), optional
      # BIN chunk. The total length field is patched in afterwards.
      def glb_string(gltf)
        json = JSON.generate(gltf).dup.force_encoding(Encoding::BINARY)
        json += " ".b * ((4 - json.bytesize % 4) % 4)

        glb = String.new(capacity: json.bytesize * 2)
        glb << [MAGIC, GLB_VERSION, 0].pack("VVV")
        glb << [json.bytesize, CHUNK_JSON].pack("VV") << json
        if @buffer.byte_length.positive?
          bin = @buffer.to_binary
          glb << [bin.bytesize, CHUNK_BIN].pack("VV") << bin
        end
        glb[8, 4] = [glb.bytesize].pack("V")
        glb
      end
    end
  end
end
