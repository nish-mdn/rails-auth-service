#!/bin/bash
set -e

# Docker entrypoint script for Rails Auth Service
# Handles database migrations, key generation, and app startup

echo "========================================="
echo "Auth Service - Docker Entrypoint"
echo "========================================="
echo ""

# Ensure log directory exists
mkdir -p /app/log

# Wait for database to be ready
echo "⏳ Waiting for database to be ready..."
max_attempts=30
attempt=1

while [ $attempt -le $max_attempts ]; do
  if mysql -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1" > /dev/null 2>&1; then
    echo "✓ Database is ready!"
    break
  fi
  
  if [ $attempt -eq $max_attempts ]; then
    echo "✗ Database did not become ready in time"
    exit 1
  fi
  
  echo "  Attempt $attempt/$max_attempts - Connection failed, retrying in 2 seconds..."
  sleep 2
  attempt=$((attempt + 1))
done

echo ""

# Run database migrations
echo "Running database migrations..."
if bundle exec rails db:migrate 2>&1; then
  echo "✓ Database migrations completed successfully"
else
  echo "✗ Database migrations failed"
  exit 1
fi

echo ""

# Generate RSA keys if they don't exist
echo "Checking RSA keys..."
if [ ! -f /app/keys/private.pem ] || [ ! -f /app/keys/public.pem ]; then
  echo "⏳ Generating RSA keys..."
  if bundle exec rails jwt:generate_keys 2>&1; then
    echo "✓ RSA keys generated successfully"
  else
    echo "✗ Failed to generate RSA keys"
    exit 1
  fi
else
  echo "✓ RSA keys already exist"
fi

echo ""

# Precompile assets (if using asset pipeline)
echo "Precompiling assets..."
if bundle exec rails assets:precompile 2>&1; then
  echo "✓ Assets precompiled successfully"
else
  echo "⚠ Asset precompilation warning (continuing anyway)"
fi

echo ""
echo "========================================="
echo "✓ Container initialization complete!"
echo "========================================="
echo ""

# Execute the main process passed as arguments
exec "$@"
