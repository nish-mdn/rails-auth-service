#!/usr/bin/env puma

# Puma configuration optimized for container deployments
# Reference: https://puma.io/puma/Puma/Configuration.html

# Configuration based on environment
rails_env = ENV.fetch('RAILS_ENV') { 'development' }

# Server concurrency
workers Integer(ENV['WEB_CONCURRENCY'] || 2)
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 16)
threads threads_count, threads_count

# Server should start in "clustered" mode i.e. with workers to handle requests
preload_app!

# The server restart command to run on hot restarts
# This option is independent of daemonization.
prune_bundler true

# Bind to specific port/socket
if ENV['RAILS_ENV'] == 'production'
  # Production: Listen on TCP port
  port ENV.fetch('PORT') { 3000 }
else
  # Development: Listen on TCP localhost
  bind "tcp://0.0.0.0:#{ENV.fetch('PORT') { 3000 }}"
end

# Socket for Unix domain socket
# bind "unix:///tmp/puma.sock"

# Environment-specific configuration
if rails_env == 'production'
  # Use all available CPU cores
  workers Integer(ENV['WEB_CONCURRENCY'] || `nproc`)
  
  # Daemonize is not recommended in Docker
  # daemonize false
  
  # Logging
  stdout_redirect ENV['LOG_PATH'] || '/app/log/puma.log',
                  ENV['LOG_ERR_PATH'] || '/app/log/puma.err.log',
                  true
  
  # Plugin support (if needed)
  # plugin :tmp_restart
  
  # Application preloading
  preload_app!
  
  # Server restart hook
  on_worker_boot do
    # Worker specific setup
    # Database connections
    ActiveSupport.on_load(:active_record) do
      ActiveRecord::Base.establish_connection
    end
  end
end

# Timeouts (for puma 5.6.9 compatibility)
# first_data_timeout: time to receive first data from client (default: 30)
# persistent_timeout: time to keep connection open (default: 20)
first_data_timeout 30
persistent_timeout 20

# Worker timeout (seconds) - default is 60
worker_timeout 60

# Tag each request with an ID
#tag_requests true

# Silence single requests from logs
#quiet true

# Maximum number of requests per connection
#max_requests_per_connection 10_000

# Allow older HTTP clients
#http_content_length_limit 1024*1024*10

# SSL support
# ssl_bind '0.0.0.0', '8443', {
#   key: '/path/to/server.key',
#   cert: '/path/to/server.crt'
# }

# Lowlevel socket options
# The socket will be set to TCP_NODELAY if true
#tcp_mode false

# Custom middleware
# app { |env| [200, {}, ['Hello']] }

# Plugin for systemd integration (if running under systemd)
# plugin :systemd

# Hook for monitoring tools integration
before_fork do |server, worker|
  # Worker specific preloads
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.connection.disconnect!
  end
end

after_worker_boot do |worker|
  # Worker specific connections
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.establish_connection
  end
  
  # Optional: Log worker information
  puts "Worker #{worker.index} booted on PID #{Process.pid}"
end

# Handle signals for graceful shutdown
# SIGTERM triggers graceful shutdown
# SIGQUIT triggers immediate shutdown without draining

# State file for monitoring
#state_path '/app/tmp/puma.state'

# Control URL (if using control server)
# control_url 'unix:///tmp/puma-control.sock'
# control_auth_token 'secret'

# Thread pool configuration for better concurrency
environment 'production' if rails_env == 'production'
