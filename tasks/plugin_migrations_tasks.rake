namespace :db do
  desc "Migrate the database through scripts in db/migrate and update db/schema.rb by invoking db:schema:dump. Target specific version with VERSION=x. Turn off output with VERBOSE=false."
  task :migrate => ['db:migrate:application', 'db:migrate:plugins']

  namespace :migrate do
    desc "Run migrations from application"
    task :application => :environment do
      ActiveRecord::Migration.verbose = ENV["VERBOSE"] ? ENV["VERBOSE"] == "true" : true
      ActiveRecord::Migrator.migrate("db/migrate/", ENV["VERSION"] ? ENV["VERSION"].to_i : nil)
      Rake::Task["db:schema:dump"].invoke if ActiveRecord::Base.schema_format == :ruby
    end
    
    desc "Run migrations from plugins"
    task :plugins => :environment do
      raise "PLUGIN is require when specify PLUGIN_VERSION" if ENV['PLUGIN_VERSION'] && !ENV['PLUGIN']

      plugins = if ENV["PLUGIN"]
        raise "Unknown plugin: #{ENV["PLUGIN"]}" unless Rails.plugins.key?(ENV["PLUGIN"])
        Hash[ENV["PLUGIN"], Rails.plugins[ENV["PLUGIN"]]]
      else
        Rails.plugins
      end

      plugins.each do |name, plugin|
        plugin_migrations_path = "#{plugin.directory}/db/migrate"
        ActiveRecord::Migration.verbose = ENV["VERBOSE"] ? ENV["VERBOSE"] == "true" : true
        ActiveRecord::Migrator.migrate(plugin_migrations_path, ENV["PLUGIN_VERSION"] ? ENV["PLUGIN_VERSION"].to_i : nil, name)
        Rake::Task["db:schema:dump"].invoke if ActiveRecord::Base.schema_format == :ruby
      end
    end
    
    namespace :plugins do
      desc 'Runs the "up" for a given PLUGIN and a given migration PLUGIN_VERSION'
      task :up => :environment do
        raise "Both PLUGIN and PLUGIN_VERSION are required" unless ENV["PLUGIN_VERSION"] && ENV["PLUGIN"]
        raise "Unknown plugin: #{ENV["PLUGIN"]}" unless Rails.plugins.key?(ENV["PLUGIN"])
        plugin_migrations_path = "#{Rails.plugins[ENV["PLUGIN"]].directory}/db/migrate"
        ActiveRecord::Migrator.run(:up, plugin_migrations_path, ENV["PLUGIN_VERSION"].to_i, ENV["PLUGIN"])
        Rake::Task["db:schema:dump"].invoke if ActiveRecord::Base.schema_format == :ruby
      end

      desc 'Runs the "down" for a given PLUGIN and a given migration PLUGIN_VERSION'
      task :down => :environment do
        raise "Both PLUGIN and PLUGIN_VERSION are required" unless ENV["PLUGIN_VERSION"] && ENV["PLUGIN"]
        raise "Unknown plugin: #{ENV["PLUGIN"]}" unless Rails.plugins.key?(ENV["PLUGIN"])
        plugin_migrations_path = "#{Rails.plugins[ENV["PLUGIN"]].directory}/db/migrate"
        ActiveRecord::Migrator.run(:down, plugin_migrations_path, ENV["PLUGIN_VERSION"].to_i, ENV["PLUGIN"])
        Rake::Task["db:schema:dump"].invoke if ActiveRecord::Base.schema_format == :ruby
      end
    end
  end
  
  desc "Raises an error if there are pending migrations"
  task :abort_if_pending_migrations => :environment do
    if defined? ActiveRecord
      pending_migrations = ActiveRecord::Migrator.new(:up, 'db/migrate').pending_migrations
      pending_migrations << Rails.plugins.map do |name, plugin|
        ActiveRecord::Migrator.new(:up, "#{plugin.directory}/db/migrate", nil, name).pending_migrations
      end
      pending_migrations.flatten!

      if pending_migrations.any?
        puts "You have #{pending_migrations.size} pending migrations:"
        pending_migrations.each do |pending_migration|
          pending_migration_string = '  %4d %s' % [pending_migration.version, pending_migration.name]
          pending_migration_string << " (#{pending_migration.plugin})" if pending_migration.plugin
          puts pending_migration_string
        end
        abort %{Run "rake db:migrate" to update your database then try again.}
      end
    end
  end

  namespace :plugins do
    desc 'Rolls the schema back to the previous version for a given PLUGIN. Specify the number of steps with STEP=n'
    task :rollback => :environment do
      raise "PLUGIN is required" unless ENV["PLUGIN"]
      raise "Unknown plugin: #{ENV["PLUGIN"]}" unless Rails.plugins.key?(ENV["PLUGIN"])
      step = ENV['STEP'] ? ENV['STEP'].to_i : 1
      plugin_migrations_path = "#{Rails.plugins[ENV["PLUGIN"]].directory}/db/migrate"
      ActiveRecord::Migrator.rollback(plugin_migrations_path, step, ENV["PLUGIN"])
      Rake::Task["db:schema:dump"].invoke if ActiveRecord::Base.schema_format == :ruby
    end

    desc 'Rollbacks the database one migration and re migrate up for a given PLUGIN. If you want to rollback more than one step, define STEP=x. Target specific version with PLUGIN_VERSION=x.'
    task :redo => :environment do
      if ENV["PLUGIN_VERSION"]
        Rake::Task["db:migrate:plugins:down"].invoke
        Rake::Task["db:migrate:plugins:up"].invoke
      else
        Rake::Task["db:plugins:rollback"].invoke
        Rake::Task["db:migrate:plugins"].invoke
      end
    end

    desc "Retrieves the current schema version number for a given PLUGIN"
    task :version => :environment do
      raise "PLUGIN is required" unless ENV["PLUGIN"]
      raise "Unknown plugin: #{ENV["PLUGIN"]}" unless Rails.plugins.key?(ENV["PLUGIN"])
      puts "Current version of #{ENV["PLUGIN"]}: #{ActiveRecord::Migrator.current_version(ENV["PLUGIN"])}"
    end
  end
end

namespace :rails do
  desc "Update both configs, scripts and public/javascripts from Rails"
  task :update => [ "update:scripts", "update:javascripts", "update:configs", "update:application_controller", "update:schema_migrations" ]
  
  namespace :update do
    desc "Update schema_migrations table structure"
    task :schema_migrations => :environment do
      sm_table = ActiveRecord::Migrator.schema_migrations_table_name
      connection = ActiveRecord::Base.connection

      unless connection.columns(sm_table).map(&:name).include?('plugin')
        connection.add_column   sm_table, :plugin, :string
        connection.remove_index sm_table, :version rescue nil
        connection.add_index [ :version, :plugin ], :unique => true,
          :name => 'unique_schema_migrations'
      end
    end
  end
end
