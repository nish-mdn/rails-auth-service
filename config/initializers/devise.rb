Devise.setup do |config|
  # Database setup
  config.mailer_sender = 'noreply@auth-service.local'

  # ORM configuration
  require 'devise/orm/active_record'

  # Case-insensitive email
  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]

  # Rememberable configuration
  config.remember_for = 4.weeks

  # Password length
  config.password_length = 8..128

  # Sign out all scopes
  config.sign_out_all_scopes = true

  # JWT Configuration
  config.jwt do |jwt|
    jwt.secret = ENV['DEVISE_JWT_SECRET_KEY'] || SecureRandom.hex(32)
    jwt.dispatch_requests = [
      ['POST', %r{^/users/sign_in$}],
      ['POST', %r{^/users$}]
    ]
    jwt.revocation_requests = [
      ['DELETE', %r{^/users/sign_out$}]
    ]
    jwt.expiration_time = 24.hours.to_i
  end
end
