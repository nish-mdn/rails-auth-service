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
# 4. REGENERATE BINSTUBS, FIX RAKEFILE, ENSURE ASSET DIRS & PERMISSIONS
# 4. REGENERATE BINSTUBS, FIX RAKEFILE, BRUTE-FORCE ASSET DIRS & PERMISSIONS
RUN bundle binstubs railties --force && \
    # 1. Fix Rakefile if missing (prevents 'No Rakefile found' error)
    if [ ! -f Rakefile ]; then \
      echo "require_relative 'config/application'\nRails.application.load_tasks" > Rakefile; \
    fi && \
    # 2. FIX: Create every possible directory Sprockets might look for
    # We include builds, javascripts, images, and vendor paths
    mkdir -p app/assets/config \
             app/assets/images \
             app/assets/stylesheets \
             app/assets/javascripts \
             app/assets/builds \
             app/javascript/controllers \
             vendor/javascript \
             vendor/assets/javascripts \
             vendor/assets/stylesheets \
             app/assets/tailwind && \
    # 3. FIX: Place a dummy file in each to ensure they aren't 'empty'
    touch app/assets/images/.keep \
          app/assets/stylesheets/.keep \
          app/assets/javascripts/.keep \
          app/assets/builds/.keep \
          vendor/javascript/.keep && \
    # 4. FIX: Ensure Tailwind entry point exists (for Tailwind v4)
    if [ ! -f app/assets/tailwind/application.css ]; then \
      echo "@tailwind base;\n@tailwind components;\n@tailwind utilities;" > app/assets/tailwind/application.css; \
    fi && \
    # 5. ASSETS: Precompile with a dummy Secret Key Base
    SECRET_KEY_BASE=dummy_key_for_build bundle exec rails assets:precompile && \
    # 6. PERMISSIONS: Finalize for the 'rails' user
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