require "workers/boot/database_connect"
require "vmdb_extensions"

require "active_support/core_ext/numeric/bytes"

require "util/extensions/miq-module"
require "util/extensions/miq-to_i_with_method"
require "default_value_for"

Workers::Autoloader.include_models("manageiq-providers-kubernetes")
Workers::Autoloader.include_models("manageiq-providers-openshift")
