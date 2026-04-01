# Master Fix for PennyWise Auth Service
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

RUN useradd -m -u 1000 rails
WORKDIR /app

# 2. INSTALL GEMS
COPY --chown=rails:rails Gemfile Gemfile.lock* ./
RUN bundle config set without 'development test' && \
    bundle install --jobs 4 --retry 3

# 3. COPY APPLICATION CODE
COPY --chown=rails:rails . .

# 4. THE ULTIMATE "BRUTE-FORCE" ASSET & CONFIG FIX
# We force every missing file to exist with correct formatting
RUN mkdir -p bin config/webpack \
             app/javascript/packs \
             app/assets/config \
             app/assets/images \
             app/assets/stylesheets \
             app/assets/javascripts \
             app/assets/builds \
             app/assets/tailwind && \
    \
    # 4a. Regenerate the MISSING bin/rails executable
    bundle binstubs railties --force && \
    \
    # 4b. Force create Rakefile
    printf "require_relative 'config/application'\nRails.application.load_tasks\n" > Rakefile && \
    \
    # 4c. Force create package.json with standard Rails JS dependencies
    printf '{"name":"auth-service","private":true,"dependencies":{"@rails/actioncable":"^6.0.0","@rails/activestorage":"^6.0.0","@rails/ujs":"^6.0.0","@rails/webpacker":"5.4.4","turbolinks":"^5.2.0","webpack":"^4.46.0","webpack-cli":"^3.3.12"},"devDependencies":{"webpack-dev-server":"^3.11.2"}}\n' > package.json && \
    \
    # 4d. Force create webpacker.yml
    printf "default: &default\n  source_path: app/javascript\n  source_entry_path: packs\n  public_root_path: public\n  public_output_path: packs\n  cache_path: tmp/webpacker\n  check_yarn_integrity: false\n\nproduction:\n  <<: *default\n  compile: false\n  extract_css: true\n  cache_manifest: true\n" > config/webpacker.yml && \
    \
    # 4e. Force create Webpack environment files (Resolves the ./src error)
    printf "const { webpackConfig } = require('@rails/webpacker')\nmodule.exports = webpackConfig\n" > config/webpack/base.js && \
    printf "process.env.NODE_ENV = process.env.NODE_ENV || 'production'\nconst webpackConfig = require('./base')\nmodule.exports = webpackConfig\n" > config/webpack/production.js && \
    \
    # 4f. Force create JS entry point (the 'Pack')
    printf "import Rails from '@rails/ujs'\nRails.start()\n" > app/javascript/packs/application.js && \
    \
    # 4g. Install JS dependencies and create Webpacker binstubs
    yarn install --check-files && \
    bundle exec rails webpacker:binstubs && \
    \
    # 4h. Force fix the manifest.js
    printf "//= link_tree ../images\n//= link_tree ../stylesheets\n//= link_tree ../javascripts\n//= link_tree ../builds\n" > app/assets/config/manifest.js && \
    \
    # 4i. Create .keep files to ensure directories are recognized
    touch app/assets/images/.keep app/assets/stylesheets/.keep app/assets/javascripts/.keep app/assets/builds/.keep && \
    \
    # 4j. Force fix Tailwind v4 and Font stubs
    printf "@tailwind base;\n@tailwind components;\n@tailwind utilities;\n" > app/assets/tailwind/application.css && \
    printf "@tailwind base;\n@tailwind components;\n@tailwind utilities;\n" > app/assets/tailwind/tailwind.css && \
    printf "/* Inter Font Stub */\n" > app/assets/stylesheets/inter-font.css && \
    \
    # 4k. ASSETS: Precompile (Now with every file and directory perfectly formatted)
    SECRET_KEY_BASE=dummy_key_for_build RAILS_ENV=production NODE_ENV=production bundle exec rails assets:precompile && \
    \
    # Finalize permissions
    chmod +x bin/* && \
    mkdir -p log tmp/pids tmp/cache tmp/sockets keys && \
    chown -R rails:rails /app

# 5. ENVIRONMENT & USER SETTINGS
ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true \
    PATH=/app/bin:$PATH

RUN chmod +x /app/docker-entrypoint.sh
USER rails
EXPOSE 3000

# 6. HEALTH CHECK
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]