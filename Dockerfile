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

# 4. INSTALL YARN DEPS & PRECOMPILE ASSETS
RUN mkdir -p log tmp/pids tmp/cache tmp/sockets keys && \
    yarn install --frozen-lockfile && \
    SECRET_KEY_BASE=dummy_key_for_build \
    RAILS_ENV=production \
    NODE_ENV=production \
    yarn add @babel/plugin-proposal-private-methods @babel/plugin-proposal-class-properties --dev && \
    bundle exec rails webpacker:install && \
    bundle exec rails assets:precompile && \
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