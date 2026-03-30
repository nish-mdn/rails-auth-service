require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module AuthService
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be configured before using the Rails application.
    # It could be a good idea to use environment variables to set these options.

    # Eager load models in development for STI to work properly
    config.eager_load_paths << Rails.root.join('app/services')

    # Autoload lib directory
    config.autoload_paths << Rails.root.join('lib')

    # Configure generators
    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot, dir: 'spec/factories'
    end

    # Set default locale
    config.i18n.default_locale = :en

    # Determine whether `config.x` should fallback to `ENV`
    config.x.use_env_for_defaults = true
  end
end
