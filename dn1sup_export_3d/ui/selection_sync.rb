# frozen_string_literal: true

module Dn1supExport3d
  # Keeps the export dialog in sync with the SketchUp selection while the
  # dialog is open: a SelectionObserver triggers a debounced push of the
  # selection's persistent ids to the page (live count in the scope card,
  # highlight in the 3D preview). Attach on show, detach on close - a leaked
  # observer would keep firing into a dead dialog.
  class SelectionSync
    DEBOUNCE_SECONDS = 0.1

    def initialize(&on_change)
      @on_change = on_change
      @observer = nil
      @timer = nil
    end

    def attach
      model = Sketchup.active_model
      return unless model
      @observer = Observer.new(method(:schedule_push))
      model.selection.add_observer(@observer)
    end

    def detach
      if @observer && (model = Sketchup.active_model)
        model.selection.remove_observer(@observer)
      end
      @observer = nil
      stop_timer
    end

    private

    # Selection events can fire per entity during rubber-band selects; the
    # debounce collapses each burst into one push.
    def schedule_push
      stop_timer
      @timer = UI.start_timer(DEBOUNCE_SECONDS, false) do
        @timer = nil
        @on_change.call
      end
    end

    def stop_timer
      UI.stop_timer(@timer) if @timer
      @timer = nil
    end

    # The official docs note that onSelectionAdded/Removed "might not
    # trigger" for tool-driven changes while onSelectionBulkChange covers
    # them - so all four events are observed; the debounce makes the
    # duplication harmless.
    class Observer < Sketchup::SelectionObserver
      def initialize(callback)
        @callback = callback
      end

      def onSelectionBulkChange(_selection)
        @callback.call
      end

      def onSelectionCleared(_selection)
        @callback.call
      end

      def onSelectionAdded(_selection, _entity)
        @callback.call
      end

      def onSelectionRemoved(_selection, _entity)
        @callback.call
      end
    end
  end
end
