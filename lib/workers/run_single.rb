module ManageIQ
  module Workers
    # Runs a single MiqWorker class in isolation
    #
    # The following rubocop rules don't apply to this file
    #
    # rubocop:disable Rails/Output, Rails/Exit
    class RunSingle
      MIQ_APP_ROOT = File.expand_path(File.join("..", ".."), __dir__)

      attr_reader   :opt_parser
      attr_accessor :options, :worker_class

      def self.run
        run_single = new
        run_single.parse_options
        run_single.run
      end

      def self.load_config_environment
        require File.join(MIQ_APP_ROOT, "config", "environment")
      end

      def initialize(options = {})
        @options = options
      end

      def run
        self.class.load_config_environment

        list_worker_types       if options[:list]
        validate_worker_type
        assign_roles            if options[:roles].present?
        configure_worker_class
        boot_worker             unless options[:dry_run]
      end

      def parse_options
        require "optparse"
        @opt_parser = OptionParser.new do |opts|
          opts.banner = "usage: #{File.basename($PROGRAM_NAME, '.rb')} MIQ_WORKER_CLASS_NAME"

          opts.on("-l", "--[no-]list", "Toggle viewing available worker class names") do |val|
            options[:list] = val
          end

          opts.on("-b", "--[no-]heartbeat", "Toggle heartbeating with worker monitor (DRB)") do |val|
            options[:heartbeat] = val
          end

          opts.on("-d", "--[no-]dry-run", "Dry run (don't create/start worker)") do |val|
            options[:dry_run] = val
          end

          opts.on("-g=GUID", "--guid=GUID", "Find an existing worker record instead of creating") do |val|
            options[:guid] = val
          end

          opts.on("-e=ems_id", "--ems-id=ems_id,ems_id", Array, "Provide a list of ems ids (without spaces) to a provider worker. This requires, at least one argument.") do |val|
            options[:ems_id] = val
          end

          opts.on("-h", "--help", "Displays this help") do
            puts opts
            exit
          end

          opts.on("-r=ROLE", "--roles=role1,role2",
                  "Set a list of active roles for the worker (comma separated, no spaces) or --roles=? to list all roles") do |val|
            if val == "?"
              puts all_role_names
              exit
            end
            options[:roles] = val.split(",")
          end
        end

        opt_parser.parse!

        # Set remaining options from remaining args and ENV
        @worker_class = ARGV[0]

        # Skip heartbeating with single worker
        ENV["DISABLE_MIQ_WORKER_HEARTBEAT"] ||= options[:heartbeat] ? nil : '1'

        # Set ems_id from ENV (if not set and exist in the ENV)
        options[:ems_id] ||= ENV["EMS_ID"]
      end

      private

      def list_worker_types
        puts MiqWorkerType.pluck(:worker_type)
        exit
      end

      def validate_worker_type
        opt_parser.abort(opt_parser.help) unless worker_class

        unless MiqWorkerType.find_by(:worker_type => worker_class)
          STDERR.puts "ERR:  `#{worker_class}` WORKER CLASS NOT FOUND!  Please run with `-l` to see possible worker class names."
          exit 1
        end
      end

      def assign_roles
        MiqServer.my_server.server_role_names += options[:roles]
        MiqServer.my_server.activate_roles(MiqServer.my_server.server_role_names)
      end

      def configure_worker_class
        self.worker_class = @worker_class.constantize
        unless worker_class.has_required_role?
          STDERR.puts "ERR:  Server roles are not sufficient for `#{worker_class}` worker."
          exit 1
        end

        worker_class.preload_for_worker_role if worker_class.respond_to?(:preload_for_worker_role)
      end

      def boot_worker
        create_options = {:pid => Process.pid}
        runner_options = {}

        if options[:ems_id]
          create_options[:queue_name] = options[:ems_id].length == 1 ? "ems_#{options[:ems_id].first}" : options[:ems_id].collect { |id| "ems_#{id}" }
          runner_options[:ems_id]     = options[:ems_id].length == 1 ? options[:ems_id].first : options[:ems_id].collect { |id| id }
        end

        worker = if options[:guid]
                   worker_class.find_by!(:guid => options[:guid]).tap do |wrkr|
                     wrkr.update(:pid => Process.pid)
                   end
                 else
                   worker_class.create_worker_record(create_options)
                 end

        begin
          runner_options[:guid] = worker.guid
          $log.info("Starting #{worker.class.name} with runner options #{runner_options}")
          worker.class::Runner.new(runner_options).tap(&:setup_sigterm_trap).start
        ensure
          FileUtils.rm_f(worker.heartbeat_file)
          $log.info("Deleting worker record for #{worker.class.name}, id #{worker.id}")
          worker.delete
        end
      end

      def all_role_names
        path = File.join(MIQ_APP_ROOT, "db", "fixtures", "server_roles.csv")
        roles = File.read(path).lines.collect do |line|
          line.split(",").first
        end
        roles.shift
        roles
      end
    end
  end
end
