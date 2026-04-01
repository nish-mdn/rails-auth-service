require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.cache_classes = true

  # Eager load code on boot.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available.
  # config.require_master_key = true

  # Disable serving static files from the `/public` folder by default.
  config.public_file_server.enabled = true

  # Do not fallback to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Store uploaded files on the local file system.
  config.active_storage.service = :local

  # Force all access to the app over SSL.
  # config.force_ssl = true

  # Log level.
  config.log_level = :info

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n.
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # --- LOGGING FIX START ---
  
  # Use ActiveSupport formatter to handle tagging correctly
  config.log_formatter = ActiveSupport::Logger::SimpleFormatter.new

  if ENV["RAILS_LOG_TO_STDOUT"].present?
    # Use ActiveSupport::Logger instead of standard Ruby Logger
    logger           = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    # Wrap the logger in TaggedLogging to support config.log_tags
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
  end
  # Add this line to skip Sass-based compression which crashes on Tailwind v4
  config.assets.css_compressor = nil
  # --- LOGGING FIX END ---

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false
end