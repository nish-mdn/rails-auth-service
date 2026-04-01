# Single-stage Dockerfile for Rails Auth Service
FROM public.ecr.aws/docker/library/ruby:3.2.0-slim

# Install all dependencies
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

# 1. Copy Gemfile and Gemfile.lock first for better caching
COPY --chown=rails:rails Gemfile Gemfile.lock* ./

# 2. Install gems
RUN bundle config set without 'development test' && \
    bundle install --jobs 4 --retry 3

# 3. Copy the rest of the application code
# This MUST happen before we try to generate binstubs
COPY --chown=rails:rails . .

# 4. FIX: Generate missing binstubs (rails, rake) while still ROOT
# This ensures they are created even if they were missing from your repo
RUN bundle binstubs railties --force && \
    chmod +x bin/* && \
    chown -R rails:rails /app/bin /app/db

# 5. Create necessary directories and ensure ownership
RUN mkdir -p /app/log /app/tmp/pids /app/tmp/cache /app/tmp/sockets /app/keys && \
    chown -R rails:rails /app/tmp /app/log /app/keys

# Set environment variables
ENV RAILS_ENV=production
ENV RACK_ENV=production
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_SERVE_STATIC_FILES=true
ENV RAILS_ROOT=/app
# Ensure /app/bin is first in the PATH so 'rails' refers to the local one
ENV PATH=/app/bin:$PATH

# Switch to rails user
USER rails

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Entrypoint script
# Note: We already copied this in step 3, but let's ensure it's executable
RUN chmod +x /app/docker-entrypoint.sh

# Start application
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]