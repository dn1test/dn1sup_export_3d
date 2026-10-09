# frozen_string_literal: true

require "json"
require "base64"
require "fileutils"
require_relative "../logger"
require_relative "../version"
require_relative "../filename"
require_relative "../exporter/glb_exporter"
require_relative "export_driver"
require_relative "selection_sync"

module Dn1supExport3d
  # Export dialog: live 3D preview on the left (built by the same exporter,
  # textures optional), settings and feedback on the right.
  #
  # Both the export and the preview run stepwise (ExportDriver on
  # UI.start_timer): progress is painted and the user can cancel between
  # steps, the UI thread never blocks for long (AGENTS.md #26). All SketchUp
  # API access happens on the UI thread; no threads are used.
  #
  # The user picks only the output folder; the GLB file name is derived from
  # the model title and restricted to Latin characters (Filename.sanitize).
  #
  # Bridge (window.sketchup.* from JS, window.exporter.* from Ruby):
  #   JS -> Ruby: dialog_ready, browse_output, export_start, export_cancel,
  #               preview_refresh, preview_object_selected, open_viewer,
  #               open_folder, open_html, close
  #   Ruby -> JS: receiveState, setOutputFolder, receiveProgress,
  #               receivePreviewStatus, receivePreviewStart/Chunk/End,
  #               receiveSelection
  class ExportDialog
    # The preview GLB travels as a base64 data URI; beyond this cap the page
    # gets a "too large" hint instead (full export + viewer dialog is the
    # intended path for huge models).
    PREVIEW_BINARY_LIMIT = 64 * 1024 * 1024
    # Base64 chars per execute_script call - keeps every bridge message
    # small enough for the CEF IPC.
    PREVIEW_CHUNK_CHARS = 1_000_000

    # Sketchup.read_default / write_default section for dialog settings.
    SETTINGS_SECTION = "dn1sup_export_3d"
    SETTINGS_LAST_FOLDER = "last_export_folder"

    # Splits a string into fixed-size chunks. Plain String#[] slicing: a
    # regexp repeat range above 100000 does not even compile in Ruby
    # (RegexpError "too big number for repeat range").
    def self.chunk_base64(str, chunk_chars)
      chunks = []
      offset = 0
      length = str.length
      while offset < length
        chunks << str[offset, chunk_chars]
        offset += chunk_chars
      end
      chunks
    end

    def self.show
      @instance ||= new
      @instance.show
    end

    def initialize
      reset_state
    end

    # Returns the HtmlDialog (nil return would make programmatic use awkward).
    def show
      reset_state
      @dialog = UI::HtmlDialog.new(
        dialog_title: "Экспорт 3D — Web 3D Export",
        preferences_key: "dn1sup_export_3d",
        width: 1200,
        height: 760,
        resizable: true
      )
      register_callbacks
      @dialog.set_file(File.join(__dir__, "export_dialog.html"))
      @dialog.set_on_closed { teardown }
      @dialog.show
      @selection_sync = SelectionSync.new { push_selection }
      @selection_sync.attach
      @dialog
    end

    private

    def register_callbacks
      @dialog.add_action_callback("dialog_ready") { push_state(include_default_folder: true) }
      @dialog.add_action_callback("browse_output") { |_ctx, current| browse_output(current) }
      @dialog.add_action_callback("export_start") { |_ctx, json| request_export(json) }
      @dialog.add_action_callback("export_cancel") { cancel_export }
      @dialog.add_action_callback("preview_refresh") { |_ctx, json| refresh_preview(json) }
      @dialog.add_action_callback("preview_object_selected") do |_ctx, *pids|
        Dn1supExport3d.select_by_persistent_id(pids)
      end
      @dialog.add_action_callback("open_viewer") { open_viewer }
      @dialog.add_action_callback("open_folder") { open_folder }
      @dialog.add_action_callback("open_html") { open_html }
      @dialog.add_action_callback("close") { @dialog.close }
    end

    # Cleanup when the dialog closed (also via the title-bar X).
    def teardown
      @driver&.stop!
      @driver = nil
      @selection_sync&.detach
      @selection_sync = nil
    end

    # A reopened dialog starts clean: leftovers from a previous session
    # (a stale error panel or result stats) must not leak into the new page.
    def reset_state
      @dialog = nil
      @mode = "idle" # idle | exporting | done | error
      @message = nil
      @stats = nil
      @warnings = []
      @glb_path = nil
      @web_dir = nil
      @single_file_path = nil
      @driver = nil
      @selection_sync = nil
    end

    # ------------------------------------------------------- state pushes

    # include_default_folder: the dialog just opened and needs the folder to
    # prefill the input (the kwarg only toggles the field, the value comes
    # from default_folder - they must not share a name).
    def push_state(include_default_folder: false)
      model = Sketchup.active_model
      state = {
        mode: @mode,
        message: @message,
        stats: @stats,
        warnings: @warnings,
        glb_name: @glb_path && File.basename(@glb_path),
        web_dir_name: @web_dir && File.basename(@web_dir),
        single_file_name: @single_file_path && File.basename(@single_file_path),
        single_file_bytes: @single_file_path && File.size(@single_file_path),
        model_name: model ? model.title.to_s : "",
        selection_count: model ? model.selection.count : 0,
        output_name: output_filename
      }
      state[:default_folder] = default_folder if include_default_folder
      execute("window.exporter.receiveState(#{json(state)});")
    end

    # Export progress: geometry phase maps to 0..90%, the post steps
    # (assembly, package, single file) fill the rest from complete_export.
    def push_progress(pct, stage, current, label)
      execute("window.exporter.receiveProgress(#{json({ pct: pct, stage: stage, current: current, label: label })});")
    end

    def push_preview_status(status, extra = {})
      execute("window.exporter.receivePreviewStatus(#{json({ status: status }.merge(extra))});")
    end

    def push_selection
      model = Sketchup.active_model
      selection = model ? model.selection : []
      pids = selection.to_a.map(&:persistent_id)
      execute("window.exporter.receiveSelection(#{json({ pids: pids, count: pids.size })});")
    end

    # JSON output is a valid JS object literal; U+2028/2029 are escaped
    # because they would terminate the script literal otherwise.
    def json(object)
      JSON.generate(object).gsub("\u2028", '\u2028').gsub("\u2029", '\u2029')
    end

    def execute(script)
      # Deferred pushes (UI.start_timer) can outlive a closed dialog.
      @dialog&.execute_script(script)
    end

    # ------------------------------------------------------ JS callbacks

    def browse_output(current)
      dir = sanitize_folder(current) || last_folder || default_folder
      # The picker must not run in the action-callback frame: execute_script
      # issued right after a native modal inside that frame is silently
      # dropped by the SU 2026 CEF (the picked folder never reached the
      # page). One deferred timer step gives both the modal and the
      # delivery a clean stack.
      UI.start_timer(0.01, false) { pick_folder(dir) }
    end

    def pick_folder(dir)
      # Confirmed against the SU 2026.2 docs: options hash, returns a String
      # (single) or Array (multi-select is not requested, but normalize).
      result = UI.select_directory(title: "Выберите папку для экспорта", directory: dir)
      return if result.nil? # Esc / Cancel - keep the current value
      folder = result.is_a?(Array) ? result.first : result
      save_last_folder(folder)
      execute("window.exporter.setOutputFolder(#{json(folder)});")
    rescue StandardError => e
      # A silent death here would leave the dialog without feedback
      # (AGENTS.md #27).
      Logger.error("Folder browse failed: #{e.class}: #{e.message}\n#{e.backtrace[0, 5].join("\n")}")
      @mode = "error"
      @message = "Не удалось выбрать папку: #{e.message}"
      push_state
    end

    def request_export(json_options)
      options = parse_options(json_options)
      unless options
        @mode = "error"
        @message = "Internal error: malformed options."
        return push_state
      end

      model = Sketchup.active_model
      scope = options["scope"] == "selection" ? :selection : :all
      if scope == :selection && (model.nil? || model.selection.empty?)
        @mode = "error"
        @message = "Selection is empty. Select objects to export first."
        return push_state
      end
      folder = sanitize_folder(options["folder"])
      unless folder
        @mode = "error"
        @message = "Укажите папку для сохранения."
        return push_state
      end
      save_last_folder(folder)
      path = File.join(folder, output_filename)

      replace_driver
      @mode = "exporting"
      @message = nil
      @stats = nil
      @warnings = []
      @glb_path = nil
      @web_dir = nil
      @single_file_path = nil
      push_state
      push_progress(0, "Подготовка", nil, "Экспорт")

      start_driver(
        kind: :export,
        model: model,
        scope: scope,
        include_hidden: !!options["include_hidden"],
        embed_textures: true,
        on_progress: ->(p) { push_progress(geometry_pct(p), "Геометрия", p[:current], "Экспорт") },
        on_done: ->(exporter) { complete_export(exporter, path, options) },
        on_cancelled: -> { export_cancelled },
        on_error: ->(e) { export_failed(e) }
      )
    end

    def cancel_export
      @driver&.cancel
    end

    def export_cancelled
      @mode = "idle"
      @message = "Экспорт отменён."
      push_state
    end

    # Runs on the UI thread between driver steps; each push paints because
    # the thread returns to SketchUp afterwards.
    def complete_export(exporter, path, options)
      push_progress(92, "Сборка GLB", nil, "Экспорт")
      glb = exporter.finish
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, glb)
      @glb_path = path
      @stats = { path: path, **exporter.summary, bytes: glb.bytesize, seconds: exporter.elapsed }
      @warnings = exporter.warnings

      @web_dir = nil
      @single_file_path = nil
      if options["web_package"]
        push_progress(96, "Веб-пакет", nil, "Экспорт")
        @web_dir = Dn1supExport3d.build_web_package(path)
      end
      if options["single_file"]
        push_progress(99, "Один HTML-файл", nil, "Экспорт")
        @single_file_path = Dn1supExport3d.build_single_file_html(path)
      end

      @mode = "done"
      @message = nil
      push_state
    rescue StandardError => e
      export_failed(e)
    end

    def export_failed(error)
      # Reported in the dialog; a silent death here would leave the dialog
      # stuck on "Exporting..." (AGENTS.md #27).
      Logger.error("GLB export failed: #{error.class}: #{error.message}\n#{error.backtrace[0, 5].join("\n")}")
      @mode = "error"
      @message = "#{error.class}: #{error.message}"
      push_state
    end

    # ------------------------------------------------------------- preview

    def refresh_preview(json_options)
      return if @driver && @driver.running? && @driver.kind == :export

      options = parse_options(json_options)
      return push_preview_status("error", message: "Internal error: malformed options.") unless options

      model = Sketchup.active_model
      scope = options["scope"] == "selection" ? :selection : :all
      if scope == :selection && (model.nil? || model.selection.empty?)
        return push_preview_status("empty_selection")
      end

      replace_driver
      push_preview_status("building", pct: 0, current: nil)
      start_driver(
        kind: :preview,
        model: model,
        scope: scope,
        include_hidden: !!options["include_hidden"],
        embed_textures: !!options["embed_textures"],
        on_progress: ->(p) { push_preview_status("building", pct: geometry_pct(p), current: p[:current]) },
        on_done: ->(exporter) { complete_preview(exporter) },
        on_cancelled: -> { push_preview_status("idle") },
        on_error: ->(e) { preview_failed(e) }
      )
    end

    def complete_preview(exporter)
      push_preview_status("assembling")
      glb = exporter.finish
      if glb.bytesize > PREVIEW_BINARY_LIMIT
        return push_preview_status("too_large", bytes: glb.bytesize)
      end

      # The preview GLB travels as a base64 data URI in chunks; the page
      # reassembles it and loads it through the engine's data: path (which
      # works on file:// too). Chunks paint between execute_script calls.
      b64 = Base64.strict_encode64(glb)
      chunks = ExportDialog.chunk_base64(b64, PREVIEW_CHUNK_CHARS)
      execute("window.exporter.receivePreviewStart(#{chunks.size});")
      chunks.each_with_index do |chunk, index|
        execute("window.exporter.receivePreviewChunk(#{index},#{json(chunk)});")
      end
      execute("window.exporter.receivePreviewEnd();")
    rescue StandardError => e
      preview_failed(e)
    end

    def preview_failed(error)
      Logger.error("Preview export failed: #{error.class}: #{error.message}\n#{error.backtrace[0, 5].join("\n")}")
      push_preview_status("error", message: "#{error.class}: #{error.message}")
    end

    # ------------------------------------------------------------- driver

    def start_driver(**args)
      @driver = ExportDriver.new(**args)
      @driver.start
    end

    # Silently stops the current driver (no callbacks) before a new one
    # starts; an export always preempts a running preview.
    def replace_driver
      @driver&.stop!
      @driver = nil
    end

    # ---------------------------------------------------------- actions

    def open_viewer
      if @web_dir
        Dn1supExport3d.show_in_dialog(File.join(@web_dir, "index.html"))
      elsif @single_file_path
        open_html
      end
    end

    def open_folder
      dir = @web_dir || (@glb_path && File.dirname(@glb_path))
      return unless dir
      UI.openURL("file:///#{dir.tr('\\', '/')}")
    end

    def open_html
      return unless @single_file_path
      UI.openURL("file:///#{@single_file_path.tr('\\', '/')}")
    end

    # ---------------------------------------------------------- helpers

    def parse_options(json_options)
      JSON.parse(json_options.to_s)
    rescue JSON::ParserError
      nil
    end

    def geometry_pct(progress)
      return 90 if progress[:total].zero?
      (progress[:done].to_f / progress[:total] * 90).round
    end

    def sanitize_folder(value)
      folder = value.to_s.strip
      return nil if folder.empty?
      File.expand_path(folder)
    end

    # The user never types a file name: it is derived from the model title,
    # Latin-only (Filename.sanitize), so the artifacts stay web-safe.
    def output_filename
      model = Sketchup.active_model
      "#{Filename.sanitize(model ? model.title.to_s : "")}.glb"
    end

    # Dialog opens in the last used folder; a fresh install falls back to the
    # model's folder (home for an unsaved model).
    def default_folder
      last_folder || model_folder
    end

    def model_folder
      model = Sketchup.active_model
      model && !model.path.to_s.empty? ? File.dirname(model.path) : Dir.home
    end

    def last_folder
      folder = Sketchup.read_default(SETTINGS_SECTION, SETTINGS_LAST_FOLDER)
      folder.is_a?(String) && !folder.empty? ? folder : nil
    end

    def save_last_folder(folder)
      Sketchup.write_default(SETTINGS_SECTION, SETTINGS_LAST_FOLDER, folder)
    end
  end
end
