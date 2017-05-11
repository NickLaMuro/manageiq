ENV['BUNDLER_GROUPS'] = "web_server,rest_api"

require File.expand_path('../../../config/application', __dir__)

Vmdb::Application.initialize!
MiqWebServiceWorker::Runner.start_worker(*ARGV)
