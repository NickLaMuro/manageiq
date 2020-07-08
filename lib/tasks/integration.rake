INTEGRATION_TMP_DIR     = Rails.root.join('tmp', 'integration')
INTEGRATION_FOREMAN_PID = INTEGRATION_TMP_DIR.join('server.pid')
INTEGRATION_FOREMAN_LOG = Rails.root.join('log', 'integration.log')
INTEGRATION_PROCFILE    = INTEGRATION_TMP_DIR.join('Procfile')
RUN_SINGLE_WORKER_BIN   = Rails.root.join('lib', 'workers', 'bin', 'run_single_worker.rb')

namespace :integration do
  desc "Seed the database"
  task :seed => [:env, "test:vmdb:setup", "evm:foreman:seed", "evm:compile_assets"]

  desc "Setup the database"
  task :setup => [:db_setup, "evm:foreman:setup"] do
    mkdir_p INTEGRATION_TMP_DIR
    rm_f    INTEGRATION_PROCFILE
    touch   INTEGRATION_PROCFILE
  end

  desc "Run a foreman server in the background"
  task :run_server => [:setup] do
    pid = File.read(INTEGRATION_FOREMAN_PID).to_i if File.exist?(INTEGRATION_FOREMAN_PID)

    if pid && (Process.getpgid(pid) rescue nil).present?
      warn "foreman process already running"
    else
      foreman_cmd = %W[
        foreman start --port=#{ENV['FOREMAN_PORT'] || '3000'}
                      --root=#{Rails.root.to_s}
                      --procfile=#{INTEGRATION_PROCFILE}
      ].join(" ")

      pid = Process.spawn(foreman_cmd, [:out, :err] => [INTEGRATION_FOREMAN_LOG, "a"])
      Process.detach(pid)
      File.write(INTEGRATION_FOREMAN_PID, pid)
    end
  end

  desc "Stop server"
  task :stop_server do
    if File.exists?(INTEGRATION_FOREMAN_PID)
      Process.kill("TERM", File.read(INTEGRATION_FOREMAN_PID).to_i)
      rm INTEGRATION_FOREMAN_PID
    else
      warn "PID file for server (#{INTEGRATION_FOREMAN_PID}) doesn't exist... moving on"
    end
  end

  desc "With a UI worker"
  task :with_ui => :setup do
    ui_config = "ui: env PORT=$PORT ruby #{RUN_SINGLE_WORKER_BIN} MiqUiWorker\n"
    File.write(INTEGRATION_PROCFILE, ui_config, :mode => "a")
  end

  task :ui_ready => :run_server do
    require 'net/http'

    loop do
      begin
        Net::HTTP.get_response(URI("http://localhost:3000/api/ping")).body == 'pong'
        break
      rescue Errno::ECONNREFUSED
        sleep 2
        retry
      end
    end

    MiqServer.my_server.update(:status => "started")
  end

  task :env do
    ENV["RAILS_ENV"] = "integration"
    ENV["RAILS_SERVE_STATIC_FILES"] = "true"
  end

  task :db_setup => [:env, :environment] do
    # Reset Rails.env and database config to make sure we are using the
    # integration environment
    Rails.env = ENV["RAILS_ENV"]
    ActiveRecord::Base.remove_connection
    ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[Rails.env])
  end
end
