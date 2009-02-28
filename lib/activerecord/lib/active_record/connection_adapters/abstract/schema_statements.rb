module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module SchemaStatements #:nodoc:
      def initialize_schema_migrations_table #:nodoc:
        sm_table = ActiveRecord::Migrator.schema_migrations_table_name

        unless tables.detect { |t| t == sm_table }
          create_table(sm_table, :id => false) do |schema_migrations_table|
            schema_migrations_table.column :version, :string, :null => false
            schema_migrations_table.column :plugin,  :string
          end
          add_index sm_table, [ :version, :plugin ], :unique => true,
            :name => 'unique_schema_migrations'

          # Backwards-compatibility: if we find schema_info, assume we've
          # migrated up to that point:
          si_table = Base.table_name_prefix + 'schema_info' + Base.table_name_suffix

          if tables.detect { |t| t == si_table }

            old_version = select_value("SELECT version FROM #{quote_table_name(si_table)}").to_i
            assume_migrated_upto_version(old_version)
            drop_table(si_table)
          end
        end
      end
    end
  end
end
