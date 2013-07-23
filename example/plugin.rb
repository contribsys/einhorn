#
# plugin.rb - An example Einhorn plugin.
#
# Including this file in [yourgemhere]/lib/einhorn/plugins/ will cause Einhorn
# to load it.  This example plugin defines all the methods that Einhorn
# recognizes and will invoke, although none of these methods is required.
#

module Einhorn::Plugins
  module ExamplePlugin
    def self.initialize_example_plugin
      # The initializer method must be named `initialize_##[plugin_name]',
      # where [plugin_name] is the name of the plugin module or class in
      # lower_case_with_underscores.
      puts 'I will be called before einhorn does any work.'
    end

    def self.optparse(opts)
      @options = {}
      opts.on("--my-option X", "Patch einhorn with additional options!") do |x|
        @options[:yay] = x
      end
    end

    def self.post_optparse
      # Called after all options native to einhorn or patched by any plugins
      # are parsed.
      @required_x = @options.fetch(:yay)
    end

    def self.event_loop
      # Called each time einhorn enters its event loop, in which it cleans up
      # any terminated children and respawns them.
    end

    def self.exit
      # Called after the event loop terminates, just before einhorn exits.
    end
  end
end
