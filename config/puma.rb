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
prune_bundler true

# Bind to specific port/socket
if ENV['RAILS_ENV'] == 'production'
  # Production: Listen on TCP port
  port ENV.fetch('PORT') { 3000 }
else
  # Development: Listen on TCP localhost
  bind "tcp://0.0.0.0:#{ENV.fetch('PORT') { 3000 }}"
end

# Environment-specific configuration
if rails_env == 'production'
  # Use all available CPU cores
  workers Integer(ENV['WEB_CONCURRENCY'] || `nproc`)
  
  # Logging
  stdout_redirect ENV['LOG_PATH'] || '/app/log/puma.log',
                  ENV['LOG_ERR_PATH'] || '/app/log/puma.err.log',
                  true
  
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

# Timeouts
first_data_timeout 30
persistent_timeout 20
worker_timeout 60

# Hook for monitoring tools integration
before_fork do |server, worker|
  # Worker specific preloads
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.connection.disconnect!
  end
end

# --- FIXED BLOCK START ---
after_worker_boot do |worker|
  # Worker specific connections
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.establish_connection
  end
  
  # FIX: 'worker' is already an Integer representing the index. 
  # Calling .index on an Integer causes the NoMethodError.
  puts "Worker #{worker} booted on PID #{Process.pid}"
end
# --- FIXED BLOCK END ---

# Thread pool configuration for better concurrency
environment 'production' if rails_env == 'production'