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
# 4. REGENERATE BINSTUBS, FIX RAKEFILE, ASSETS & PERMISSIONS
RUN bundle binstubs railties --force && \
    # Fix Rakefile (as we did before)
    if [ ! -f Rakefile ]; then \
      echo "require_relative 'config/application'" > Rakefile; \
      echo "Rails.application.load_tasks" >> Rakefile; \
    fi && \
    # FIX: Ensure Tailwind entry point exists
    mkdir -p app/assets/tailwind && \
    if [ ! -f app/assets/tailwind/application.css ]; then \
      echo "@tailwind base;\n@tailwind components;\n@tailwind utilities;" > app/assets/tailwind/application.css; \
    fi && \
    # Precompile assets during build (Best Practice for Production)
    # Use dummy values for Secret Key Base if it's not set yet
    SECRET_KEY_BASE=dummy_key_for_build bundle exec rails assets:precompile && \
    # Ensure all executables are actually executable
    chmod +x bin/* && \
    mkdir -p log tmp/pids tmp/cache tmp/sockets keys && \
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