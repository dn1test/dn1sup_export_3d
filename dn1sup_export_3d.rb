# frozen_string_literal: true

require "sketchup.rb"

# Extension registrar. This file sits next to the dn1sup_export_3d/ folder,
# both in this repository and inside an installed RBZ/Plugins folder.
module Dn1supExport3d
  unless file_loaded?("dn1sup_export_3d.rb")
    entry_file = File.join(__dir__, "dn1sup_export_3d", "main.rb")
    if File.file?(entry_file)
      ext = SketchupExtension.new("Web 3D Export (dn1sup)", File.join(__dir__, "dn1sup_export_3d", "main.rb"))
      ext.description = "Export SketchUp models (or the current selection) to GLB and view them in a browser or HtmlDialog (Three.js)."
      version_file = File.join(__dir__, "dn1sup_export_3d", "version.rb")
      begin
        if File.file?(version_file)
          require version_file
        else
          require File.expand_path(File.join(__dir__, "dn1sup_export_3d", "version"))
        end
      rescue LoadError
        # Битая установка (напр. неполный клон профиля: есть .rb, нет папки
        # с version.rb) — расширение всё равно регистрируется, версия-заглушка.
        VERSION = "0.0.0" unless defined?(VERSION)
      end
      ext.version = VERSION
      ext.creator = "DN1Sup"
      ext.copyright = "2026 DN1Sup (MIT License)"
      ext.id = "dn1sup_export_3d" if ext.respond_to?(:id=)
      Sketchup.register_extension(ext, true)
    else
      # Битый профиль (есть .rb, нет папки с main.rb): пропускаем регистрацию
      # вместо модальной ошибки SketchUp «Failed to load file».
      warn "[dn1sup_export_3d] пропущен: нет #{entry_file} — переустановите расширение или профиль"
    end
  end
  file_loaded("dn1sup_export_3d.rb")
end
