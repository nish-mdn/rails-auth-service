# Single-stage Dockerfile for Rails Auth Service
FROM public.ecr.aws/docker/library/ruby:3.2.0-slim

# 1. System Dependencies
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libmariadb-dev \
    pkg-config \
    libmariadb3 \
    default-mysql-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN useradd -m -u 1000 rails
WORKDIR /app

# 2. Gem Installation (Optimized for caching)
# IMPORTANT: Ensure Gemfile.lock is REMOVED from your .dockerignore file
COPY --chown=rails:rails Gemfile Gemfile.lock* ./
RUN bundle config set without 'development test' && \
    bundle install --jobs 4 --retry 3

# 3. Copy Application Code
COPY --chown=rails:rails . .

# 4. REGENERATE BINSTUBS, FIX RAKEFILE & PERMISSIONS
# We do this as ROOT to avoid "Permission Denied" errors
RUN bundle binstubs railties --force && \
    # FIX: If Rakefile is missing, create a minimal one so 'rails db:migrate' can run
    if [ ! -f Rakefile ]; then \
      echo "require_relative 'config/application'" > Rakefile; \
      echo "Rails.application.load_tasks" >> Rakefile; \
    fi && \
    # Ensure all executables are actually executable
    chmod +x bin/* && \
    # Create necessary directories
    mkdir -p log tmp/pids tmp/cache tmp/sockets keys && \
    # Final ownership sweep to ensure the 'rails' user owns EVERYTHING in /app
    chown -R rails:rails /app

# 5. Environment & User Settings
ENV RAILS_ENV=production \
    RACK_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true \
    PATH=/app/bin:$PATH

USER rails
EXPOSE 3000

# 6. Health Check (Uses the /health endpoint we fixed in production.rb)
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# 7. Entrypoint & Execution
# Ensure the entrypoint has correct permissions
RUN chmod +x /app/docker-entrypoint.sh
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]