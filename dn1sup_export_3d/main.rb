# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "version"
require_relative "logger"
require_relative "exporter/glb_exporter"

module Dn1supExport3d
  MENU_TITLE = "Web 3D Export"

  def self.menu_activate(scope = :all)
    model = Sketchup.active_model
    return UI.messagebox("No open model.") if model.nil?
    if scope == :selection && model.selection.empty?
      return UI.messagebox("Selection is empty. Select objects to export first.")
    end
    default_name = model.title.to_s.empty? ? "model" : model.title
    dir = model.path.to_s.empty? ? Dir.home : File.dirname(model.path)
    path = UI.savepanel("Export GLB", dir, "#{default_name}.glb")
    return unless path
    path += ".glb" unless path.downcase.end_with?(".glb")
    export(path, scope: scope)
  end

  def self.export(glb_path, scope: :all)
    model = Sketchup.active_model
    exporter = Exporter::GLBExporter.new(model: model, scope: scope)
    exporter.export(glb_path)

    web_dir = build_web_package(glb_path)
    show_in_dialog(File.join(web_dir, "index.html"))
    [glb_path, web_dir]
  rescue StandardError => e
    # Deliberate top-level report: the user must see a useful message even
    # when SketchUp swallows the re-raised error (AGENTS.md #27).
    msg = "GLB export failed.\n\nReason:\n#{e.class}: #{e.message}\n\n" \
          "Backtrace:\n#{e.backtrace[0, 5].join("\n")}"
    Logger.error(msg)
    UI.messagebox(msg)
    raise
  end

  # ------------------------------------------------------------- viewer

  # Shows the exported web package in an HtmlDialog. The Ruby -> JS direction
  # uses execute_script, JS -> Ruby uses the skp: action-callback scheme
  # (see README, "HtmlDialog bridge").
  def self.show_in_dialog(index_url)
    close_dialog
    dialog = UI::HtmlDialog.new(
      dialog_title: "Web 3D Viewer",
      preferences_key: "dn1sup_export_3d",
      width: 1000,
      height: 700,
      resizable: true
    )
    # Callbacks must be attached before #show (they are cleared on close).
    dialog.add_action_callback("viewer_ready") do |_context, object_count|
      Logger.info("Viewer ready (#{object_count} selectable objects)")
    end
    # The viewer sends the whole ancestor chain of pids (part -> instance);
    # the first one that exists as an entity in the model gets selected.
    dialog.add_action_callback("object_selected") do |_context, *pids|
      select_by_persistent_id(pids)
    end
    dialog.set_file(File.expand_path(index_url))
    dialog.show
    @dialog = dialog # keep a reference: an unreferenced HtmlDialog can be GC'ed
    dialog
  end

  def self.close_dialog
    @dialog.close if @dialog && @dialog.visible?
  ensure
    @dialog = nil
  end

  # Selects the first entity of the given pid chain that exists in the model
  # (the viewer reports part pid first, its component instance last).
  def self.select_by_persistent_id(pids)
    model = Sketchup.active_model
    Array(pids).each do |pid|
      entity = find_by_persistent_id(model.entities, pid.to_s)
      next unless entity
      model.selection.clear
      model.selection.add(entity)
      Logger.info("Selected from viewer: #{entity.name.to_s.empty? ? entity.typename : entity.name} (#{entity.persistent_id})")
      return entity
    end
    Logger.warn("Object(s) #{Array(pids).join(', ')} reported by viewer were not found in the model")
    nil
  end

  def self.find_by_persistent_id(entities, pid, visited = {})
    entities.each do |entity|
      return entity if entity.persistent_id.to_s == pid
      next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      if entity.is_a?(Sketchup::ComponentInstance)
        # Shared definitions: search their content only once.
        next if visited.key?(entity.definition.persistent_id)
        visited[entity.definition.persistent_id] = true
      end
      container = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
      found = find_by_persistent_id(container, pid, visited)
      return found if found
    end
    nil
  end

  # --------------------------------------------------------- web package

  # Copies the GLB plus viewer assets next to it so the package can be
  # uploaded as-is (AGENTS.md #23): <name>_web3d/{model.glb, index.html,
  # viewer.js, viewer.css, vendor/three/*}.
  def self.build_web_package(glb_path)
    base = File.basename(glb_path, ".glb")
    web_dir = File.join(File.dirname(glb_path), "#{base}_web3d")
    FileUtils.mkdir_p(web_dir)
    FileUtils.cp(glb_path, File.join(web_dir, "model.glb"))
    src = File.join(__dir__, "viewer")
    %w[index.html viewer.js viewer.css].each do |file|
      FileUtils.cp(File.join(src, file), web_dir)
    end
    # vendor/ is copied as a whole tree (three/ ES modules + utils/ that
    # GLTFLoader.js imports from).
    FileUtils.rm_rf(File.join(web_dir, "vendor"))
    FileUtils.cp_r(File.join(__dir__, "vendor"), web_dir)
    web_dir
  end
end

module Dn1supExport3d
  unless file_loaded?("dn1sup_export_3d/main.rb")
    menu = UI.menu("Plugins").add_submenu(MENU_TITLE)
    menu.add_item("Export current model to GLB") { menu_activate(:all) }
    menu.add_item("Export selected objects to GLB") { menu_activate(:selection) }
    file_loaded("dn1sup_export_3d/main.rb")
  end
end
