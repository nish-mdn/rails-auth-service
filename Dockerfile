# Single-stage Dockerfile for Rails Auth Service (PennyWise)
FROM public.ecr.aws/docker/library/ruby:3.2.0-slim

# 1. INSTALL ALL SYSTEM DEPENDENCIES (Node, Yarn, Build Essentials, MariaDB)
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libmariadb-dev \
    pkg-config \
    libmariadb3 \
    default-mysql-client \
    curl \
    gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install nodejs -y \
    && npm install --global yarn \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN useradd -m -u 1000 rails
WORKDIR /app

# 2. INSTALL GEMS
# CRITICAL: Ensure Gemfile.lock is REMOVED from your .dockerignore file
COPY --chown=rails:rails Gemfile Gemfile.lock* ./
RUN bundle config set without 'development test' && \
    bundle install --jobs 4 --retry 3

# 3. COPY APPLICATION CODE
COPY --chown=rails:rails . .

# 4. THE FINAL "UNSTOPPABLE" BUILD BLOCK
# This fixes binstubs, Rakefile, missing directories, and assets in one shot
RUN # 4a. Generate ALL necessary binstubs (Rails, Rake, and Webpacker) \
    bundle binstubs railties webpacker --force && \
    \
    # 4b. Fix Rakefile if missing (prevents 'No Rakefile found' error) \
    if [ ! -f Rakefile ]; then \
      echo "require_relative 'config/application'\nRails.application.load_tasks" > Rakefile; \
    fi && \
    \
    # 4c. Brute-force create all directories referenced in manifest.js \
    mkdir -p app/assets/config \
             app/assets/images \
             app/assets/stylesheets \
             app/assets/javascripts \
             app/assets/builds \
             app/javascript/controllers \
             vendor/javascript \
             app/assets/tailwind && \
    touch app/assets/images/.keep \
          app/assets/stylesheets/.keep \
          app/assets/javascripts/.keep \
          app/assets/builds/.keep \
          vendor/javascript/.keep && \
    \
    # 4d. Fix Tailwind v4 entry point \
    if [ ! -f app/assets/tailwind/application.css ]; then \
      echo "@tailwind base;\n@tailwind components;\n@tailwind utilities;" > app/assets/tailwind/application.css; \
    fi && \
    \
    # 4e. ASSETS: Precompile (Node and Webpacker stubs are now present) \
    SECRET_KEY_BASE=dummy_key_for_build \
    RAILS_ENV=production \
    NODE_ENV=production \
    bundle exec rails assets:precompile && \
    \
    # 4f. PERMISSIONS: Finalize for the 'rails' user \
    chmod +x bin/* && \
    mkdir -p log tmp/pids tmp/cache tmp/sockets keys && \
    chown -R rails:rails /app

# 5. ENVIRONMENT & USER SETTINGS
ENV RAILS_ENV=production \
    RACK_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true \
    PATH=/app/bin:$PATH

USER rails
EXPOSE 3000

# 6. HEALTH CHECK
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# 7. ENTRYPOINT & EXECUTION
RUN chmod +x /app/docker-entrypoint.sh
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]