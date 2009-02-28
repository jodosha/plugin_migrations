module ActiveRecord #:nodoc:
  class MigrationProxy #:nodoc:
    attr_accessor :plugin
  end
  
  class Migrator #:nodoc:
    class << self
      def migrate(migrations_path, target_version = nil, plugin_name = nil)
        case
          when target_version.nil?                           then up(migrations_path, target_version, plugin_name)
          when current_version(plugin_name) > target_version then down(migrations_path, target_version, plugin_name)
          else                                                    up(migrations_path, target_version, plugin_name)
        end
      end

      def rollback(migrations_path, steps=1, plugin_name = nil)
        migrator = self.new(:down, migrations_path, nil, plugin_name)
        start_index = migrator.migrations.index(migrator.current_migration)
        return unless start_index
        
        finish = migrator.migrations[start_index + steps]
        down(migrations_path, finish ? finish.version : 0, plugin_name)
      end

      def up(migrations_path, target_version = nil, plugin_name = nil)
        self.new(:up, migrations_path, target_version, plugin_name).migrate
      end

      def down(migrations_path, target_version = nil, plugin_name = nil)
        self.new(:down, migrations_path, target_version, plugin_name).migrate
      end
      
      def run(direction, migrations_path, target_version, plugin_name = nil)
        self.new(direction, migrations_path, target_version, plugin_name).run
      end

      def get_all_versions(plugin_name = nil)
        Base.connection.select_values("SELECT version FROM #{schema_migrations_table_name} WHERE plugin #{plugin_name ? "= '#{plugin_name}'" : "IS NULL"}").map(&:to_i).sort
      end

      def current_version(plugin_name = nil)
        sm_table = schema_migrations_table_name
        if Base.connection.table_exists?(sm_table)
          get_all_versions(plugin_name).max || 0
        else
          0
        end
      end
    end
    
    def initialize(direction, migrations_path, target_version = nil, plugin_name = nil)
      raise StandardError.new("This database does not yet support migrations") unless Base.connection.supports_migrations?
      Base.connection.initialize_schema_migrations_table
      @direction, @migrations_path, @target_version, @plugin_name = direction, migrations_path, target_version, plugin_name
    end
    
    def migrations
      @migrations ||= begin
        files = Dir["#{@migrations_path}/[0-9]*_*.rb"]
        
        migrations = files.inject([]) do |klasses, file|
          version, name = file.scan(/([0-9]+)_([_a-z0-9]*).rb/).first
          
          raise IllegalMigrationNameError.new(file) unless version
          version = version.to_i
          
          if klasses.detect { |m| m.version == version }
            raise DuplicateMigrationVersionError.new(version) 
          end

          if klasses.detect { |m| m.name == name.camelize }
            raise DuplicateMigrationNameError.new(name.camelize) 
          end
          
          klasses << returning(MigrationProxy.new) do |migration|
            migration.name     = name.camelize
            migration.version  = version
            migration.filename = file
            migration.plugin   = @plugin_name
          end
        end
        
        migrations = migrations.sort_by(&:version)
        down? ? migrations.reverse : migrations
      end
    end
    
    def migrated
      @migrated_versions ||= self.class.get_all_versions(@plugin_name)
    end

    private
      def record_version_state_after_migrating(version)
        sm_table = self.class.schema_migrations_table_name

        @migrated_versions ||= []
        if down?
          @migrated_versions.delete(version.to_i)
          Base.connection.update(@plugin_name ?
            "DELETE FROM #{sm_table} WHERE version = '#{version}' AND plugin = '#{@plugin_name}'" :
            "DELETE FROM #{sm_table} WHERE version = '#{version}'")
        else
          @migrated_versions.push(version.to_i).sort!
          Base.connection.insert(@plugin_name ?
            "INSERT INTO #{sm_table} (version, plugin) VALUES ('#{version}', '#{@plugin_name}')" :
            "INSERT INTO #{sm_table} (version) VALUES ('#{version}')")
        end
      end
  end
end
