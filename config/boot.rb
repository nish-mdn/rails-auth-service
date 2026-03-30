ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' # Set up gems listed in the Gemfile.

# Bootsnap is optional for production - only load if it's available
begin
  require 'bootsnap/setup'
rescue LoadError
  # bootsnap not installed, continue without it
end
