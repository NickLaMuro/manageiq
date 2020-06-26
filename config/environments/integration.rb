# Settings for integration testings.  A mix between develpment and production,
# using production as a base and pulling in specific options from development
# where appropriate.
#
Vmdb::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb

  config.eager_load_paths = []

  # Code is not reloaded between requests unless CYPRESS_DEV is set
  #
  # Idea borrowed from:
  #
  #   https://blog.simplificator.com/2019/10/11/setting-up-cypress-with-rails/
  #
  config.cache_classes = !ENV['CYPRESS_DEV']
  config.eager_load = false

  # Log error messages when you accidentally call methods on nil.
  config.whiny_nils = true

  # Full error reports are disabled and caching is turned on
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = false

  # Don't care if the mailer can't send
  config.action_mailer.raise_delivery_errors = false

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Disable serving static files from the `/public` folder by default since
  # Apache or NGINX already handles this.
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?

  # Compress JavaScripts and CSS
  config.assets.compress = !ENV['CYPRESS_DEV']

  # Do not fallback to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Generate digests for assets URLs
  config.assets.digest = true

  # Include miq_debug in the list of assets here because it is only used in development
  config.assets.precompile << 'miq_debug.js'
  config.assets.precompile << 'miq_debug.css'

  # See everything in the log (default is :info)
  config.log_level = :debug

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation can not be found)
  config.i18n.fallbacks = [I18n.default_locale]

  # Do not include all helpers for all views
  config.action_controller.include_all_helpers = false

  config.action_controller.allow_forgery_protection = true

  config.assets.css_compressor = :sass
end
