# main.rb
require "json"
require "fileutils"

module Dn1supExport3d
  VERSION = "0.1.0".freeze

  def self.menu_activate
    model = Sketchup.active_model
    return UI.messagebox("No open model.") if model.nil?
    default_name = model.title.to_s.empty? ? "model" : model.title
    dir = model.path.to_s.empty? ? Dir.home : File.dirname(model.path)
    path = UI.savepanel("Export GLB", dir, "#{default_name}.glb")
    return unless path
    path += ".glb" unless path.downcase.end_with?(".glb")
    export(path)
  end

  def self.export(glb_path)
    model = Sketchup.active_model
    exporter = Exporter::GLBExporter.new(model: model, scope: :all)
    exporter.export(glb_path)

    web_dir = build_web_package(glb_path)
    index = File.join(web_dir, "index.html")
    show_in_dialog(index)
    [glb_path, web_dir]
  rescue StandardError => e
    msg = "GLB export failed.\n\nReason:\n#{e.class}: #{e.message}\n\nBacktrace:\n#{e.backtrace[0, 5].join("\n")}"
    UI.messagebox(msg)
    raise
  end

  def self.show_in_dialog(index_url)
    file_url = "file:///#{File.expand_path(index_url).tr('\\', '/')}"
    dialog = UI::HtmlDialog.new(
      dialog_title: "Web 3D Viewer",
      preferences_key: "dn1sup_export_3d",
      width: 1000,
      height: 700,
      resizable: true
    )
    dialog.set_file(File.expand_path(index_url))
    dialog.show
    file_url
  end

  def self.build_web_package(glb_path)
    base = File.basename(glb_path, ".glb")
    web_dir = File.join(File.dirname(glb_path), "#{base}_web3d")
    FileUtils.mkdir_p(web_dir)
    FileUtils.cp(glb_path, File.join(web_dir, "model.glb"))
    src = File.join(__dir__, "viewer")
    FileUtils.cp(File.join(src, "index.html"), web_dir)
    FileUtils.cp(File.join(src, "viewer.js"), web_dir)
    FileUtils.cp(File.join(src, "viewer.css"), web_dir)
    vendor_src = File.join(__dir__, "vendor", "three")
    vendor_dst = File.join(web_dir, "vendor", "three")
    FileUtils.mkdir_p(vendor_dst)
    Dir.children(vendor_src).each { |f| FileUtils.cp(File.join(vendor_src, f), vendor_dst) }
    web_dir
  end
end

module Dn1supExport3d
  unless file_loaded?("dn1sup_export_3d_main.rb")
    menu = UI.menu("Plugins").add_submenu("Web 3D Export")
    menu.add_item("Export current model to GLB") { Dn1supExport3d.menu_activate }
    file_loaded("dn1sup_export_3d_main.rb")
  end
end
