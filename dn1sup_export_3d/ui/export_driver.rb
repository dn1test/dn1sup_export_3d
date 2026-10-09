# frozen_string_literal: true

require_relative "../exporter/glb_exporter"

module Dn1supExport3d
  # Drives a stepwise GLBExporter from UI.start_timer so the SketchUp UI
  # thread stays responsive between steps (AGENTS.md #26): the dialog paints
  # progress and delivers action callbacks (e.g. cancel) while a big model
  # exports. All SketchUp API access stays on the UI thread; no threads.
  #
  # The timer is a self-rearming one-shot: while a step runs there is no
  # pending timer, so stop! never kills a callback mid-flight and action
  # callbacks can only interleave between steps.
  #
  # One driver runs at a time; the owner (ExportDialog) stop!s the previous
  # one before starting the next. kind is :export or :preview - the owner
  # lets an export preempt a running preview.
  class ExportDriver
    STEP_SECONDS = 0.15
    TICK_SECONDS = 0.05

    attr_reader :kind, :exporter

    def initialize(kind:, model:, scope:, include_hidden:, embed_textures:,
                   on_progress:, on_done:, on_cancelled:, on_error:)
      @kind = kind
      @model = model
      @scope = scope
      @include_hidden = include_hidden
      @embed_textures = embed_textures
      @on_progress = on_progress
      @on_done = on_done
      @on_cancelled = on_cancelled
      @on_error = on_error
      @cancelled = false
      @timer = nil
      @exporter = nil
    end

    def running?
      !@timer.nil?
    end

    def cancelled?
      @cancelled
    end

    # User-facing cancel: stops after the current step and reports through
    # on_cancelled.
    def cancel
      @cancelled = true
    end

    # Silent teardown (replacing the driver, dialog closing): no callbacks.
    def stop!
      stop
    end

    def start
      @exporter = Exporter::GLBExporter.new(
        model: @model,
        scope: @scope,
        include_hidden: @include_hidden,
        embed_textures: @embed_textures
      )
      @exporter.begin_export
      arm
    rescue StandardError => e
      stop
      @on_error.call(e)
    end

    private

    def arm
      @timer = UI.start_timer(TICK_SECONDS, false) { tick }
    end

    def tick
      @timer = nil
      done = @exporter.step(STEP_SECONDS)
      @on_progress.call(@exporter.progress)
      if @cancelled
        @on_cancelled.call
      elsif done
        @on_done.call(@exporter)
      else
        arm
      end
    rescue StandardError => e
      stop
      @on_error.call(e)
    end

    def stop
      UI.stop_timer(@timer) if @timer
      @timer = nil
    end
  end
end
