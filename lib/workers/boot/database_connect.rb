##### Attach Global Methods #####
include Vmdb::GlobalMethods


##### Intialize Loggers #####
Vmdb::Loggers.init


##### Intialize Local Settings #####

# Required because we aren't activating this normally through the railtie
require "config"
Config.load_and_set_settings(Config.setting_files(ManageIQ.root.join('config'), ::ManageIQ.env))

require "extensions/descendant_loader"

Vmdb::Settings.init
Vmdb::Loggers.apply_config(::Settings.log)


##### Connect to the Database #####
db_config = ManageIQ::ActiveRecordConnector::ConnectionConfig.database_configuration
ManageIQ::ActiveRecordConnector.establish_connection_if_needed db_config
