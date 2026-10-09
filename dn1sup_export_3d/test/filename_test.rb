# frozen_string_literal: true

# Model-title -> Latin file name conversion used by the export dialog and
# the quick-export menu (pure Ruby, no SketchUp API).
require_relative "test_helper"

Dn1supTest.test("Filename: Cyrillic transliterates (passport scheme)") do
  Dn1supTest.assert_equal("Kukhnya-Mechta_2.0", Dn1supExport3d::Filename.sanitize("Кухня-Мечта 2.0"))
  Dn1supTest.assert_equal("Tablitsa", Dn1supExport3d::Filename.sanitize("Таблица"))
  Dn1supTest.assert_equal("Elka-elka", Dn1supExport3d::Filename.sanitize("Ёлка-ёлка"))
  Dn1supTest.assert_equal("Obekt_1_final", Dn1supExport3d::Filename.sanitize("Объект №1 (финал)"))
  Dn1supTest.assert_equal("Ivan_Sidorov", Dn1supExport3d::Filename.sanitize("Иван_Сидоров"))
end

Dn1supTest.test("Filename: case is preserved on transliteration") do
  Dn1supTest.assert_equal("ShchUKA", Dn1supExport3d::Filename.sanitize("ЩУКА"))
  Dn1supTest.assert_equal("Mechta", Dn1supExport3d::Filename.sanitize("Мечта"))
end

Dn1supTest.test("Filename: ASCII names pass through") do
  Dn1supTest.assert_equal("English_Only-123", Dn1supExport3d::Filename.sanitize("English_Only-123"))
  Dn1supTest.assert_equal("Model_v1.2", Dn1supExport3d::Filename.sanitize("Model v1.2"))
end

Dn1supTest.test("Filename: unsupported characters collapse to _") do
  Dn1supTest.assert_equal("a_b", Dn1supExport3d::Filename.sanitize("a   b"))
  Dn1supTest.assert_equal("a_b", Dn1supExport3d::Filename.sanitize("a///b"))
  Dn1supTest.assert_equal("50_sm._shkaf", Dn1supExport3d::Filename.sanitize("50 см. шкаф"))
end

Dn1supTest.test("Filename: empty or unusable falls back to model") do
  Dn1supTest.assert_equal("model", Dn1supExport3d::Filename.sanitize(""))
  Dn1supTest.assert_equal("model", Dn1supExport3d::Filename.sanitize("   "))
  Dn1supTest.assert_equal("model", Dn1supExport3d::Filename.sanitize("!!!___"))
  Dn1supTest.assert_equal("model", Dn1supExport3d::Filename.sanitize(nil))
end

Dn1supTest.test("Filename: result is Latin-only and length-capped") do
  long = Dn1supExport3d::Filename.sanitize("Длинное " + "имя" * 60)
  Dn1supTest.assert(long.length <= 100, "length #{long.length} > 100")
  Dn1supTest.assert(long.match?(/\A[A-Za-z0-9._-]+\z/), "non-Latin characters remain: #{long.inspect}")
  Dn1supTest.assert(long !~ /[._]\z/, "trailing separator after truncation: #{long.inspect}")
end
