module ::Rails
  class << self
    def plugins
      @@plugins ||= ActiveSupport::OrderedHash.new
    end
  end
  
  class Plugin
    class Loader
      protected
        def register_plugin_as_loaded(plugin)
          initializer.loaded_plugins << plugin
          Rails.plugins[plugin.name] = plugin
        end
    end
  end
end
