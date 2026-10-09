# frozen_string_literal: true

require "json"
require "base64"
require "fileutils"
require_relative "version"
require_relative "logger"
require_relative "filename"
require_relative "exporter/glb_exporter"
require_relative "ui/export_dialog"

module Dn1supExport3d
  MENU_TITLE = "Web 3D Export"
  ICONS_DIR = File.join(__dir__, "icons")

  def self.export_command
    @export_command ||= begin
      cmd = UI::Command.new("Export to GLB") { ExportDialog.show }
      cmd.small_icon = File.join(ICONS_DIR, "export_16.png")
      cmd.large_icon = File.join(ICONS_DIR, "export_24.png")
      cmd.tooltip = "Export to GLB"
      cmd.status_bar_text = "Export the model or the current selection to GLB"
      cmd.menu_text = "Export to GLB\u2026"
      cmd
    end
  end

  def self.create_toolbar
    return @toolbar if @toolbar
    @toolbar = UI::Toolbar.new(MENU_TITLE)
    @toolbar.add_item(export_command)
    @toolbar.restore
    @toolbar
  end

  def self.menu_activate(scope = :all)
    model = Sketchup.active_model
    return UI.messagebox("No open model.") if model.nil?
    if scope == :selection && model.selection.empty?
      return UI.messagebox("Selection is empty. Select objects to export first.")
    end
    default_name = Filename.sanitize(model.title)
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

  # Copies the GLB plus the built viewer next to it so the package can be
  # uploaded as-is (AGENTS.md #23): <name>_web3d/{model.glb, index.html,
  # README.txt, THIRD-PARTY-NOTICES.txt, assets/}. With single_file: true it
  # also writes <name>.html next to the folder - one self-contained file
  # (viewer plus the model as base64) that a customer can open by
  # double-click.
  def self.build_web_package(glb_path, single_file: false)
    base = File.basename(glb_path, ".glb")
    web_dir = File.join(File.dirname(glb_path), "#{base}_web3d")
    FileUtils.mkdir_p(web_dir)
    FileUtils.cp(glb_path, File.join(web_dir, "model.glb"))
    src = File.join(__dir__, "viewer")
    FileUtils.cp(File.join(src, "index.html"), File.join(web_dir, "index.html"))
    # Layouts from older exports must not survive a re-export.
    %w[viewer.js viewer.css vendor].each { |stale| FileUtils.rm_rf(File.join(web_dir, stale)) }
    assets = File.join(src, "assets")
    FileUtils.rm_rf(File.join(web_dir, "assets"))
    FileUtils.cp_r(assets, web_dir) if File.directory?(assets)
    # The bundled three.js/Vue.js keep their MIT notice in every distributed
    # artifact (AGENTS.md #34).
    FileUtils.cp(
      File.join(__dir__, "THIRD-PARTY-NOTICES.txt"),
      File.join(web_dir, "THIRD-PARTY-NOTICES.txt")
    )
    File.write(
      File.join(web_dir, "README.txt"),
      web_package_readme(base),
      encoding: "UTF-8"
    )
    build_single_file_html(glb_path) if single_file
    web_dir
  end

  # Path of the self-contained HTML file (next to the GLB).
  def self.single_file_path(glb_path)
    File.join(File.dirname(glb_path), "#{File.basename(glb_path, ".glb")}.html")
  end

  # Inlines the built viewer (Vite embeds css into the js for IIFE builds,
  # but a separate stylesheet is handled too) and the GLB itself (base64
  # data URI) into one HTML file. The engine reads
  # window.__VIEWER_BOOT.model, so the file works even over file://, where
  # browsers forbid fetching neighboring files.
  def self.build_single_file_html(glb_path)
    src = File.join(__dir__, "viewer")
    assets = File.join(src, "assets")
    html = File.read(File.join(src, "index.html"))
    html = html.gsub(%r{<script\b[^>]*src="\./assets/[^"]+"[^>]*>\s*</script>}) do |tag|
      js = File.read(File.join(assets, File.basename(tag[/src="([^"]+)"/, 1])))
      # A literal "</script>" inside the code would close the element.
      "<script>#{js.gsub('</script') { '<\/script' }}</script>"
    end
    html = html.gsub(%r{<link\b[^>]*href="\./assets/[^"]+"[^>]*>}) do |tag|
      css = File.read(File.join(assets, File.basename(tag[/href="([^"]+)"/, 1])))
      "<style>#{css}</style>"
    end
    b64 = Base64.strict_encode64(File.binread(glb_path))
    boot = "<script>window.__VIEWER_BOOT={model:'data:model/gltf-binary;base64,#{b64}'," \
           "name:#{JSON.generate(File.basename(glb_path))}};</script>"
    # A single file travels alone, so the license notice goes into it as an
    # HTML comment (AGENTS.md #34). The texts are also at
    # github.com/mrdoob/three.js (LICENSE) and github.com/vuejs/core (LICENSE).
    notice = "<!-- Bundled software: three.js (MIT, (c) 2010-2026 three.js authors), " \
             "Vue.js (MIT, (c) 2018-present, Yuxi (Evan) You). -->"
    html = html.sub(/<head>/i, "<head>\n#{notice}\n#{boot}")
    File.binwrite(single_file_path(glb_path), html)
    single_file_path(glb_path)
  end

  def self.web_package_readme(base)
    <<~TEXT
      Просмотр 3D-модели
      ==================

      Эта папка предназначена для размещения на веб-хостинге (точка входа -
      index.html) или для просмотра из SketchUp (расширение Web 3D Export).

      Чтобы отправить модель заказчику одним файлом, используйте файл
      #{base}.html рядом с папкой: модель встроена в него, и он открывается
      двойным кликом в любом современном браузере.

      THIRD-PARTY-NOTICES.txt - лицензии сторонних библиотек (three.js,
      Vue.js), встроенных в просмотрщик.
    TEXT
  end
end

module Dn1supExport3d
  unless file_loaded?("dn1sup_export_3d/main.rb")
    menu = UI.menu("Plugins").add_submenu(MENU_TITLE)
    menu.add_item(export_command)
    menu.add_separator
    menu.add_item("Quick export current model to GLB") { menu_activate(:all) }
    menu.add_item("Quick export selection to GLB") { menu_activate(:selection) }
    create_toolbar
    file_loaded("dn1sup_export_3d/main.rb")
  end
end
