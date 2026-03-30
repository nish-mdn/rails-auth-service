Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Silence deprecation warnings
  if ENV['RAILS_MASTER_KEY'].blank? && !ENV['SKIP_CREDENTIALS'].present?
    # Credentials are optional - not all apps use encrypted credentials
  end

  # Settings for logging
  config.log_level = :debug
end
