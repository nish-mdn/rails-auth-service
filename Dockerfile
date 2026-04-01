# Single-stage Dockerfile for Rails Auth Service (PennyWise) [cite: 1]
FROM public.ecr.aws/docker/library/ruby:3.2.0-slim

# 1. INSTALL SYSTEM DEPENDENCIES (Ruby 3.2.0, Node 20, Yarn) [cite: 1, 2, 3]
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential git libmariadb-dev pkg-config libmariadb3 default-mysql-client curl gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install nodejs -y \
    && npm install --global yarn \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 rails
WORKDIR /app

# 2. INSTALL GEMS
COPY --chown=rails:rails Gemfile Gemfile.lock* ./
RUN bundle config set without 'development test' && \
    bundle install --jobs 4 --retry 3

# 3. COPY APPLICATION CODE
COPY --chown=rails:rails . .

# 4. THE MASTER CONFIGURATION & ASSET FIX (No internal comments to avoid shell errors)
RUN if [ ! -f Rakefile ]; then \
      echo "require_relative 'config/application'\nRails.application.load_tasks" > Rakefile; \
    fi && \
    mkdir -p config/webpack app/javascript/packs && \
    if [ ! -f config/webpacker.yml ]; then \
      echo "default: &default\n  source_path: app/javascript\n  source_entry_path: packs\n  public_root_path: public\n  public_output_path: packs\n  cache_path: tmp/webpacker\n  check_yarn_integrity: false\n\nproduction:\n  <<: *default\n  compile: false\n  extract_css: true\n  cache_manifest: true" > config/webpacker.yml; \
    fi && \
    if [ ! -f config/webpack/base.js ]; then \
      echo "const { webpackConfig } = require('@rails/webpacker')\nmodule.exports = webpackConfig" > config/webpack/base.js; \
    fi && \
    if [ ! -f config/webpack/production.js ]; then \
      echo "process.env.NODE_ENV = process.env.NODE_ENV || 'production'\nconst webpackConfig = require('./base')\nmodule.exports = webpackConfig" > config/webpack/production.js; \
    fi && \
    if [ ! -f app/javascript/packs/application.js ]; then \
      echo "import Rails from '@rails/ujs'\nRails.start()" > app/javascript/packs/application.js; \
    fi && \
    bundle binstubs railties --force && \
    bundle exec rails webpacker:binstubs && \
    mkdir -p app/assets/config app/assets/images app/assets/stylesheets \
             app/assets/javascripts app/assets/builds app/assets/tailwind \
             vendor/javascript && \
    touch app/assets/images/.keep app/assets/stylesheets/.keep \
          app/assets/javascripts/.keep app/assets/builds/.keep && \
    echo "//= link_tree ../images\n//= link_tree ../stylesheets\n//= link_tree ../javascripts\n//= link_tree ../builds" > app/assets/config/manifest.js && \
    echo "@tailwind base;\n@tailwind components;\n@tailwind utilities;" > app/assets/tailwind/application.css && \
    echo "@tailwind base;\n@tailwind components;\n@tailwind utilities;" > app/assets/tailwind/tailwind.css && \
    if [ ! -f app/assets/stylesheets/inter-font.css ]; then \
      echo "/* Inter Font Stub */" > app/assets/stylesheets/inter-font.css; \
    fi && \
    SECRET_KEY_BASE=dummy_key_for_build RAILS_ENV=production NODE_ENV=production bundle exec rails assets:precompile && \
    chmod +x bin/* && \
    mkdir -p log tmp/pids tmp/cache tmp/sockets keys && \
    chown -R rails:rails /app

# 5. ENVIRONMENT & USER
ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true \
    PATH=/app/bin:$PATH

RUN chmod +x /app/docker-entrypoint.sh

USER rails
EXPOSE 3000

# 6. HEALTH CHECK
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1 [cite: 13]

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]