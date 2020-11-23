#!/usr/bin/env rake
# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require File.expand_path('../config/application', __FILE__)
require File.expand_path('../lib/tasks/evm_rake_helper', __FILE__)

include Rake::DSL

if defined?(ActiveRecord::DatabaseConfigurations::DatabaseConfig)
  ActiveRecord::DatabaseConfigurations::DatabaseConfig # autoload (hopefully)

  # puts
  # puts "Before:"
  begin
    ActiveRecord::DatabaseConfigurations.walk_configs(ENV["RAILS_ENV"], "before", "url" => "postgresql:///not_existing_db?host=/var/lib/postgresql")
  rescue => e
    # puts e.message
  end
  # puts

  module ActiveRecord
    module DatabaseConfigurations
      def self.walk_configs(env_name, spec_name, config)
        # puts "  .walk_configs(#{env_name.inspect}, #{spec_name.inspect}, #{config.inspect})"
        if config["database"] || config["url"] || config["adapter"]
          DatabaseConfig.new(env_name, spec_name, config)
        else
          config.each_pair.map do |sub_spec_name, sub_config|
            walk_configs(env_name, sub_spec_name, sub_config)
          end
        end
      end

      def self.db_configs(configs = ActiveRecord::Base.configurations) # :nodoc:
        # puts
        # puts
        # puts "  .db_configs(#{configs.inspect})"
        # puts
        # puts
        configs.each_pair.flat_map do |env_name, config|
          walk_configs(env_name, "primary", config)
        end
      end
    end
  end

  # puts
  # puts "After:"
  ActiveRecord::DatabaseConfigurations.walk_configs(ENV["RAILS_ENV"], "before", "url" => "postgresql:///not_existing_db?host=/var/lib/postgresql")
  # puts

elsif defined?(ActiveRecord::Core::DatabaseConfig)
  ActiveRecord::Core # autoload (hopefully)

  # puts
  # puts "Before:"
  begin
    ActiveRecord::Core.walk_configs(ENV["RAILS_ENV"], "before", "url" => "postgresql:///not_existing_db?host=/var/lib/postgresql")
  rescue => e
    # puts e.message
  end
  # puts

  module ActiveRecord
    module Core
      def self.walk_configs(env_name, spec_name, config)
        # puts "  .walk_configs(#{env_name.inspect}, #{spec_name.inspect}, #{config.inspect})"
        if config["database"] || config["url"] || config["adapter"]
          DatabaseConfig.new(env_name, spec_name, config)
        else
          config.each_pair.map do |sub_spec_name, sub_config|
            walk_configs(env_name, sub_spec_name, sub_config)
          end
        end
      end
    end
  end

  # puts
  # puts "After:"
  ActiveRecord::Core.walk_configs(ENV["RAILS_ENV"], "before", "url" => "postgresql:///not_existing_db?host=/var/lib/postgresql")
  # puts
end

Vmdb::Application.load_tasks

# Clear noisy and unusable tasks added by rspec-rails
if defined?(RSpec)
  Rake::Task.tasks.select { |t| t.name =~ /^spec(:)?/ }.each(&:clear)
end
