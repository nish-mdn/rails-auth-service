# Single-stage Dockerfile for Rails Auth Service (PennyWise)
FROM public.ecr.aws/docker/library/ruby:3.2.0-slim

# 1. INSTALL SYSTEM DEPENDENCIES (Ruby 3.2.0, Node 20, Yarn)
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential git libmariadb-dev pkg-config libmariadb3 default-mysql-client curl gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install nodejs -y \
    && npm install --global yarn \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 rails
WORKDIR /app

# 2. INSTALL GEMS
# Ensure Gemfile.lock is NOT in your .dockerignore
COPY --chown=rails:rails Gemfile Gemfile.lock* ./
RUN bundle config set without 'development test' && \
    bundle install --jobs 4 --retry 3

# 3. COPY APPLICATION CODE
COPY --chown=rails:rails . .

# 4. THE "UNSTOPPABLE" ASSET & PERMISSION FIX
RUN # 4a. Generate binstubs for Rails and Webpacker \
    bundle binstubs railties webpacker --force && \
    \
    # 4b. Fix Rakefile if missing (prevents 'No Rakefile found' error) \
    if [ ! -f Rakefile ]; then \
      echo "require_relative 'config/application'\nRails.application.load_tasks" > Rakefile; \
    fi && \
    \
    # 4c. Create all required asset directories \
    mkdir -p app/assets/config app/assets/images app/assets/stylesheets \
             app/assets/javascripts app/assets/builds app/assets/tailwind \
             app/javascript/controllers vendor/javascript && \
    touch app/assets/images/.keep app/assets/stylesheets/.keep \
          app/assets/javascripts/.keep app/assets/builds/.keep && \
    \
    # 4d. FIX: Update manifest.js to include the 'builds' folder \
    echo "//= link_tree ../images\n//= link_tree ../stylesheets\n//= link_tree ../javascripts\n//= link_tree ../builds" > app/assets/config/manifest.js && \
    \
    # 4e. FIX: Create tailwind.css input to match your stylesheet_link_tag "tailwind" \
    if [ ! -f app/assets/tailwind/tailwind.css ]; then \
      echo "@tailwind base;\n@tailwind components;\n@tailwind utilities;" > app/assets/tailwind/tailwind.css; \
    fi && \
    \
    # 4f. FIX: Stub inter-font.css so the layout doesn't crash \
    if [ ! -f app/assets/stylesheets/inter-font.css ]; then \
      echo "/* Inter Font Stub */" > app/assets/stylesheets/inter-font.css; \
    fi && \
    \
    # 4g. ASSETS: Precompile for production \
    SECRET_KEY_BASE=dummy_key_for_build \
    RAILS_ENV=production NODE_ENV=production \
    bundle exec rails assets:precompile && \
    \
    # 4h. PERMISSIONS: Finalize for the rails user \
    chmod +x bin/* && \
    mkdir -p log tmp/pids tmp/cache tmp/sockets keys && \
    chown -R rails:rails /app

# 5. ENVIRONMENT & USER
ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true \
    PATH=/app/bin:$PATH

USER rails
EXPOSE 3000

# 6. HEALTH CHECK (using the fixed production.rb logger)
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]