# frozen_string_literal: true

module Dn1supExport3d
  # Output file names are derived from the model title, but restricted to
  # Latin letters, digits and "_-. " so the exported artifacts (GLB, HTML,
  # web package) survive any browser, hosting and zip tool regardless of the
  # model's language (AGENTS.md #13, #23). Cyrillic uses the passport
  # transliteration scheme (GOST R 52535.1 / ICAO). No SketchUp API here -
  # unit-testable.
  module Filename
    MAX_LENGTH = 100

    # Keyed by lowercase source letter; uppercase input capitalizes the
    # mapping ("Ж" -> "Zh"). Hard signs map to "" (omitted, per the scheme).
    TRANSLIT = {
      "а" => "a", "б" => "b", "в" => "v", "г" => "g", "д" => "d",
      "е" => "e", "ё" => "e", "ж" => "zh", "з" => "z", "и" => "i",
      "й" => "y", "к" => "k", "л" => "l", "м" => "m", "н" => "n",
      "о" => "o", "п" => "p", "р" => "r", "с" => "s", "т" => "t",
      "у" => "u", "ф" => "f", "х" => "kh", "ц" => "ts", "ч" => "ch",
      "ш" => "sh", "щ" => "shch", "ъ" => "", "ы" => "y", "ь" => "",
      "э" => "e", "ю" => "yu", "я" => "ya"
    }.freeze

    ALLOWED = /[A-Za-z0-9._-]/.freeze

    # "Кухня-Мечта 2.0" -> "Kuhnya-Mechta_2.0". Everything the table and
    # ALLOWED cannot represent becomes "_"; runs collapse, edge separators
    # are trimmed, an empty result falls back to "model".
    def self.sanitize(name)
      cleaned = name.to_s.strip.chars.map { |ch| convert(ch) }.join
      cleaned = cleaned.gsub(/[^A-Za-z0-9._-]+/, "_")
      cleaned = cleaned[0, MAX_LENGTH] if cleaned.length > MAX_LENGTH
      cleaned = cleaned.gsub(/\A[._]+|[._]+\z/, "")
      cleaned.empty? ? "model" : cleaned
    end

    # Single-character conversion: translit for Cyrillic (case preserved),
    # the character itself for allowed ASCII, a space placeholder for
    # everything else (collapsed to "_" by sanitize).
    def self.convert(ch)
      mapped = TRANSLIT[ch.downcase]
      return mapped.capitalize if mapped && ch != ch.downcase
      return mapped if mapped
      ALLOWED.match?(ch) ? ch : " "
    end
  end
end
