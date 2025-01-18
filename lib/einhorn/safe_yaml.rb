require "yaml"

module Einhorn
  module SafeYAML
    begin
      YAML.safe_load("---", permitted_classes: [])
    rescue ArgumentError
      def self.load(payload)
        YAML.safe_load(payload, [Set, Symbol, Time, Einhorn::Bind::Inet, Einhorn::Bind::Unix], [], true)
      end
    else
      def self.load(payload) # rubocop:disable Lint/DuplicateMethods
        YAML.safe_load(payload, permitted_classes: [Set, Symbol, Time, Einhorn::Bind::Inet, Einhorn::Bind::Unix], aliases: true)
      end
    end
  end
end
