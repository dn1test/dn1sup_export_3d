# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../logger"
require_relative "../version"

module Dn1supExport3d
  # User-facing export interface (AGENTS.md Phase 9): scope, output path,
  # options, feedback and post-export actions, built on the HtmlDialog
  # bridge (window.sketchup.* from JS, execute_script from Ruby).
  #
  # The export itself runs synchronously on the SketchUp UI thread - the
  # SketchUp API is not thread-safe - so the dialog shows an indeterminate
  # "Exporting..." state; the timer below just lets the callback return
  # first so that state actually gets painted before the block starts.
  class ExportDialog
    def self.show
      @instance ||= new
      @instance.show
    end

    def initialize
      @dialog = nil
      @mode = "idle"
      @message = nil
      @stats = nil
      @web_dir = nil
    end

    # Returns the HtmlDialog (nil return would make programmatic use awkward).
    def show
      @dialog = UI::HtmlDialog.new(
        dialog_title: "Export to GLB",
        preferences_key: "dn1sup_export_3d",
        width: 500,
        height: 430,
        resizable: false
      )
      register_callbacks
      @dialog.set_file(File.join(__dir__, "export_dialog.html"))
      @dialog.show
      @dialog
    end

    private

    def register_callbacks
      @dialog.add_action_callback("dialog_ready") { push_state(default_path: true) }
      @dialog.add_action_callback("browse_output") { |_ctx, current| browse_output(current) }
      @dialog.add_action_callback("export_start") { |_ctx, json| request_export(json) }
      @dialog.add_action_callback("cancel") { @dialog.close }
      @dialog.add_action_callback("open_viewer") { open_viewer }
      @dialog.add_action_callback("open_folder") { open_folder }
    end

    # ------------------------------------------------------- state pushes

    def push_state(default_path: false)
      model = Sketchup.active_model
      state = {
        mode: @mode,
        message: @message,
        stats: @stats,
        web_dir_name: @web_dir && File.basename(@web_dir),
        selection_count: model ? model.selection.count : 0
      }
      state[:default_path] = default_path if default_path
      execute("window.exporter.receiveState(#{json(state)});")
    end

    # JSON output is a valid JS object literal; U+2028/2029 are escaped
    # because they would terminate the script literal otherwise.
    def json(object)
      JSON.generate(object).gsub("\u2028", '\u2028').gsub("\u2029", '\u2029')
    end

    def execute(script)
      @dialog.execute_script(script)
    end

    # ------------------------------------------------------ JS callbacks

    def browse_output(current)
      current = current.to_s
      fallback = default_path
      path = UI.savepanel(
        "Save GLB",
        current.empty? ? File.dirname(fallback) : File.dirname(current),
        current.empty? ? File.basename(fallback) : File.basename(current)
      )
      return unless path
      execute("window.exporter.setOutputPath(#{json(path)});")
    end

    def request_export(json_options)
      options = begin
        JSON.parse(json_options.to_s)
      rescue JSON::ParserError
        nil
      end
      unless options.is_a?(Hash)
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
      path = sanitize_path(options["path"])
      unless path
        @mode = "error"
        @message = "Specify the output .glb file."
        return push_state
      end

      @mode = "exporting"
      @message = "Exporting\u2026"
      @stats = nil
      push_state
      UI.start_timer(0.05, false) { run_export(model, scope, path, !!options["include_hidden"]) }
    end

    def run_export(model, scope, path, include_hidden)
      exporter = Exporter::GLBExporter.new(model: model, scope: scope, include_hidden: include_hidden)
      stats = exporter.export(path)
      web_dir = build_web_package(path)
      @web_dir = web_dir
      @mode = "done"
      @message = nil
      @stats = stats
      push_state
    rescue StandardError => e
      # Reported in the dialog; a silent death here would leave the dialog
      # stuck on "Exporting..." (AGENTS.md #27).
      Logger.error("GLB export failed: #{e.class}: #{e.message}\n#{e.backtrace[0, 5].join("\n")}")
      @mode = "error"
      @message = "#{e.class}: #{e.message}"
      @stats = nil
      push_state
    end

    def open_viewer
      return unless @web_dir
      Dn1supExport3d.show_in_dialog(File.join(@web_dir, "index.html"))
    end

    def open_folder
      return unless @web_dir
      UI.openURL("file:///#{File.dirname(@web_dir).tr('\\', '/')}")
    end

    # ---------------------------------------------------------- helpers

    def sanitize_path(value)
      path = value.to_s.strip
      return nil if path.empty?
      path = File.expand_path(path)
      path += ".glb" unless path.downcase.end_with?(".glb")
      path
    end

    def default_path
      model = Sketchup.active_model
      title = model && !model.title.to_s.empty? ? model.title : "model"
      dir = model && !model.path.to_s.empty? ? File.dirname(model.path) : Dir.home
      File.join(dir, "#{title}.glb")
    end

    # Defined in main.rb; reachable through the enclosing namespace.
    def build_web_package(glb_path)
      Dn1supExport3d.build_web_package(glb_path)
    end
  end
end
