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

# Copy Gemfile and Gemfile.lock
COPY --chown=rails:rails Gemfile Gemfile.lock* ./

# Install gems
RUN bundle install --jobs 4 --retry 3 --without development test

# Copy application code
COPY --chown=rails:rails . .

# Create necessary directories
RUN mkdir -p /app/log /app/tmp/pids /app/tmp/cache /app/tmp/sockets

# Set environment variables
ENV RAILS_ENV=production
ENV RACK_ENV=production
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_SERVE_STATIC_FILES=true

# Switch to rails user
USER rails

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Entrypoint script
COPY --chown=rails:rails docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# Start application
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
