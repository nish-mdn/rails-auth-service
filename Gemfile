source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.2.0"

gem "rails", "~> 7.0.0"
gem "mysql2", "~> 0.5"
gem "puma", "~> 5.0"
gem "sass-rails", ">= 6"
gem "webpacker", "~> 5.0"
gem "turbolinks-rails"
gem "jbuilder", "~> 2.7"
gem "redis", "~> 4.0"
gem "bcrypt", "~> 3.1.7"
gem "image_processing", "~> 1.2"
gem "aws-sdk-s3", require: false

# Authentication & JWT
gem "devise"
gem "devise-jwt"
gem "ruby-jwt"

# Security & CORS
gem "rack-cors"

# Styling
gem "tailwindcss-rails"

# Development and Testing
group :development, :test do
  gem "byebug", platforms: [:mri, :mingw, :x64_mingw]
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
end

group :development do
  gem "web-console", ">= 4.1.0"
  gem "listen", "~> 3.3"
  gem "spring"
end

group :test do
  gem "capybara", ">= 3.26"
  gem "selenium-webdriver"
end

gem "tzinfo-data", platforms: [:mingw, :mswin, :x64_mingw, :jruby]
