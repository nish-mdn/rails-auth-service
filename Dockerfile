FROM public.ecr.aws/docker/library/ruby:3.2.0-slim

# 1. System Dependencies
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential git libmariadb-dev pkg-config libmariadb3 default-mysql-client curl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 rails
WORKDIR /app

# 2. Gem Installation (Optimized for caching)
# Note: Remove Gemfile.lock from .dockerignore so this works!
COPY --chown=rails:rails Gemfile Gemfile.lock* ./
RUN bundle config set without 'development test' && \
    bundle install --jobs 4 --retry 3

# 3. Copy Application Code
COPY --chown=rails:rails . .

# 4. REGENERATE BINSTUBS & FIX PERMISSIONS
# We do this as ROOT to ensure we have permission to write to /app/bin
RUN bundle exec rake rails:update:bin && \
    bundle binstubs railties --force && \
    chmod +x bin/* && \
    # Create logs/tmp and ensure the rails user owns EVERYTHING
    mkdir -p log tmp/pids tmp/cache tmp/sockets keys && \
    chown -R rails:rails /app

# 5. Environment & User
ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    PATH=/app/bin:$PATH

USER rails
EXPOSE 3000

# 6. Entrypoint
# Ensure the entrypoint is executable
RUN chmod +x /app/docker-entrypoint.sh
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]