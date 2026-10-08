# dn1sup_export_3d.rb
require "sketchup.rb"

module Dn1supExport3d
  unless file_loaded?("dn1sup_export_3d.rb")
    ext = SketchupExtension.new("Web 3D Export (dn1sup)", File.join(__dir__, "dn1sup_export_3d", "main.rb"))
    ext.description = "Export SketchUp model to GLB and view it in a web page (Three.js)."
    ext.version = "0.1.0"
    ext.creator = "dn1desn"
    ext.copyright = "MIT License"
    Sketchup.register_extension(ext, true)
  end
  file_loaded("dn1sup_export_3d.rb")
end
