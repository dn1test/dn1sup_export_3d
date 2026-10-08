# frozen_string_literal: true

require "sketchup.rb"

# Extension registrar. This file sits next to the dn1sup_export_3d/ folder,
# both in this repository and inside an installed RBZ/Plugins folder.
module Dn1supExport3d
  unless file_loaded?("dn1sup_export_3d.rb")
    ext = SketchupExtension.new("Web 3D Export (dn1sup)", File.join(__dir__, "dn1sup_export_3d", "main.rb"))
    ext.description = "Export SketchUp models (or the current selection) to GLB and view them in a browser or HtmlDialog (Three.js)."
    require File.expand_path(File.join(__dir__, "dn1sup_export_3d", "version"))
    ext.version = VERSION
    ext.creator = "dn1desn"
    ext.copyright = "2026, dn1desn (MIT License)"
    Sketchup.register_extension(ext, true)
  end
  file_loaded("dn1sup_export_3d.rb")
end
