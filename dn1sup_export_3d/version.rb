# frozen_string_literal: true

# Single authoritative source of the extension version (see AGENTS.md #36).
module Dn1supExport3d
  VERSION = "0.8.6".freeze
  # DEV-вариант живёт в Plugins/<id>_dev/ — признак по имени корневой папки
  # (version.rb лежит в корне папки расширения)
  DEV_BUILD = File.basename(__dir__).end_with?("_dev").freeze
end
