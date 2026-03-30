namespace :jwt do
  desc 'Generate RSA key pair for JWT signing'
  task :generate_keys => :environment do
    JwtService.generate_keys
  end
end
