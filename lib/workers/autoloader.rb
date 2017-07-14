require 'pathname'
require "active_support/dependencies"

module Workers
  class Autoloader
    APP_ROOT = Pathname.new(File.expand_path("../../..", __FILE__))

    class << self
      def include_lib(gem = nil)
        root = gem ? find_root(gem) : APP_ROOT
        lib_paths = [
          root.join("lib"),
          root.join("lib", "services"),
          root.join("lib", "workers")
        ]
        add_autoload_paths lib_paths
      end

      def include_models(gem = nil)
        root = gem ? find_root(gem) : APP_ROOT
        model_paths = [
          root.join("app", "models"),
          root.join("app", "models", "aliases"),
          root.join("app", "models", "mixins")
        ]
        add_autoload_paths model_paths
      end

      private

      def add_autoload_paths(paths)
        loadable_paths = paths.select { |path| File.exist? path }
        ActiveSupport::Dependencies.autoload_paths.unshift *loadable_paths
      end

      def find_root(gem)
        Pathname.new(Gem::Specification.find_by_name(gem).gem_dir)
      end
    end
  end
end
