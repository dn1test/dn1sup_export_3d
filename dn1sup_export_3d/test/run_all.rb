# frozen_string_literal: true

# Test runner: force-loads extension + helper code (SketchUp caches
# require_relative for the whole session, so plain requires would run stale
# code on repeated runs), then loads every *_test.rb and prints a summary.
# Usage inside SketchUp:  load "<repo>/dn1sup_export_3d/test/run_all.rb"
extension_root = File.expand_path("..", __dir__)
%w[
  version.rb
  logger.rb
  exporter/coordinate.rb
  exporter/buffer.rb
  exporter/materials.rb
  exporter/geometry.rb
  exporter/glb_exporter.rb
  test/support/glb_parser.rb
  test/test_helper.rb
].each { |relative| load(File.join(extension_root, relative)) }

# Reloading re-assigns constants; silence the "already initialized" noise.
old_verbose = $VERBOSE
$VERBOSE = nil
begin
  Dir.glob(File.expand_path("*_test.rb", __dir__)).sort.each { |file| load(file) }
ensure
  $VERBOSE = old_verbose
end
Dn1supTest.report
