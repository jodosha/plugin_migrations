module Commands #:nodoc:
  class Plugin #:nodoc:
    def options
      OptionParser.new do |o|
        o.set_summary_indent('  ')
        o.banner =    "Usage: #{@script_name} [OPTIONS] command"
        o.define_head "Rails plugin manager."
        
        o.separator ""        
        o.separator "GENERAL OPTIONS"
        
        o.on("-r", "--root=DIR", String,
             "Set an explicit rails app directory.",
             "Default: #{@rails_root}") { |rails_root| @rails_root = rails_root; self.environment = RailsEnvironment.new(@rails_root) }
        o.on("-s", "--source=URL1,URL2", Array,
             "Use the specified plugin repositories instead of the defaults.") { |sources| @sources = sources}
        
        o.on("-v", "--verbose", "Turn on verbose output.") { |verbose| $verbose = verbose }
        o.on("-h", "--help", "Show this help message.") { puts o; exit }
        
        o.separator ""
        o.separator "COMMANDS"
        
        o.separator "  discover   Discover plugin repositories."
        o.separator "  list       List available plugins."
        o.separator "  install    Install plugin(s) from known repositories or URLs."
        o.separator "  update     Update installed plugins."
        o.separator "  remove     Uninstall plugins."
        o.separator "  source     Add a plugin source repository."
        o.separator "  unsource   Remove a plugin repository."
        o.separator "  sources    List currently configured plugin repositories."
        o.separator "  rename     Rename a plugin in the migrations table."
        
        o.separator ""
        o.separator "EXAMPLES"
        o.separator "  Install a plugin:"
        o.separator "    #{@script_name} install continuous_builder\n"
        o.separator "  Install a plugin from a subversion URL:"
        o.separator "    #{@script_name} install http://dev.rubyonrails.com/svn/rails/plugins/continuous_builder\n"
        o.separator "  Install a plugin from a git URL:"
        o.separator "    #{@script_name} install git://github.com/SomeGuy/my_awesome_plugin.git\n"
        o.separator "  Install a plugin and add a svn:externals entry to vendor/plugins"
        o.separator "    #{@script_name} install -x continuous_builder\n"
        o.separator "  List all available plugins:"
        o.separator "    #{@script_name} list\n"
        o.separator "  List plugins in the specified repository:"
        o.separator "    #{@script_name} list --source=http://dev.rubyonrails.com/svn/rails/plugins/\n"
        o.separator "  Discover and prompt to add new repositories:"
        o.separator "    #{@script_name} discover\n"
        o.separator "  Discover new repositories but just list them, don't add anything:"
        o.separator "    #{@script_name} discover -l\n"
        o.separator "  Add a new repository to the source list:"
        o.separator "    #{@script_name} source http://dev.rubyonrails.com/svn/rails/plugins/\n"
        o.separator "  Remove a repository from the source list:"
        o.separator "    #{@script_name} unsource http://dev.rubyonrails.com/svn/rails/plugins/\n"
        o.separator "  Show currently configured repositories:"
        o.separator "    #{@script_name} sources\n"  
        o.separator "  Rename a plugin:"
        o.separator "    #{@script_name} rename continuous-builder continuous_builder\n"  
      end
    end
  end
  
  def parse!(args=ARGV)
    general, sub = split_args(args)
    options.parse!(general)
    
    command = general.shift
    if command =~ /^(list|discover|install|source|unsource|sources|remove|update|rename|info)$/
      command = Commands.const_get(command.capitalize).new(self)
      command.parse!(sub)
    else
      puts "Unknown command: #{command}"
      puts options
      exit 1
    end
  end
  
  class Rename
    def initialize(base_command)
      require File.expand_path(File.join(RAILS_ROOT, 'config', 'environment'))
      @base_command = base_command
    end

    def options
      OptionParser.new do |o|
        o.set_summary_indent('  ')
        o.banner =    "Usage: #{@base_command.script_name} rename OLD_NAME NEW_NAME"
        o.define_head "Rename a plugin in the migrations table."
      end
    end

    def parse!(args)
      options.parse!(args)
      old_name, new_name = args

      ActiveRecord::Base.transaction do
        FileUtils.mv(File.join(RAILS_ROOT, 'vendor', 'plugins', old_name),
          File.join(RAILS_ROOT, 'vendor', 'plugins', new_name))

        sanitized_sql = ActiveRecord::Base.send(:sanitize_sql, "UPDATE #{ActiveRecord::Migrator.schema_migrations_table_name} set plugin = '#{new_name}' WHERE plugin = '#{old_name}'")
        ActiveRecord::Base.connection.update(sanitized_sql)
      end

      puts "Renamed #{old_name} in #{new_name}"
    end
  end
end
