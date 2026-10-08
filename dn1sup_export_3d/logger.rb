# frozen_string_literal: true

module Dn1supExport3d
  # Minimal tagged logger (AGENTS.md #28). Output goes to the Ruby console
  # (stdout). Debug messages are opt-in via Logger.debug = true.
  module Logger
    @debug_enabled = false

    class << self
      attr_accessor :debug_enabled

      def debug(message)
        puts "[dn1sup_export_3d][debug] #{message}" if @debug_enabled
      end

      def info(message)
        puts "[dn1sup_export_3d] #{message}"
      end

      def warn(message)
        puts "[dn1sup_export_3d][warn] #{message}"
      end

      def error(message)
        puts "[dn1sup_export_3d][error] #{message}"
      end
    end
  end
end
