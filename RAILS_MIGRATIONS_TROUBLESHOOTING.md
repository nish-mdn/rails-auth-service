# Rails Migrations in Docker - Troubleshooting Guide

## Problem
When running `bundle exec rails db:migrate` inside a running container, you receive:
```
Usage: rails new APP_PATH [options]
```
This error indicates that Rails cannot properly initialize your application and is defaulting to the `rails new` command.

## Root Cause
This typically happens when:
1. **RAILS_ENV is not set** - Rails defaults to "development" mode, which can cause initialization issues
2. **Working directory is incorrect** - You need to be in `/app` directory
3. **Bundler context is not established** - The Gemfile context is lost when manually running commands
4. **Missing database configuration** - The database connection details aren't available

## Solution

### During Container Startup (Automatic)
The entrypoint script (`docker-entrypoint.sh`) now automatically:
- Sets `RAILS_ENV=production` and `RACK_ENV=production`
- Changes to the `/app` directory
- Properly initializes Bundler
- Runs migrations before starting the application

**This means migrations should run automatically on container startup.**

### When Manually Running Commands Inside Container

If you need to run Rails commands manually inside a running container, you have two options:

#### Option 1: Use the Helper Script (Recommended)
```bash
# Inside the container
source /app/docker/rails-cli-helper.sh

# Now run Rails commands
bundle exec rails db:migrate
bundle exec rails console
bundle exec rails db:seed
```

#### Option 2: Manual Environment Setup
```bash
# Inside the container
export RAILS_ENV=production
export RACK_ENV=production
export RAILS_LOG_TO_STDOUT=true
export RAILS_SERVE_STATIC_FILES=true
cd /app

# Now run Rails commands
bundle exec rails db:migrate
```

#### Option 3: Run Command with Environment Variables
```bash
# Direct command from host (simpler)
docker exec -it auth-service-app bash
# Then run your command
bundle exec rails db:migrate
```

Or all-in-one:
```bash
docker exec -it \
  -e RAILS_ENV=production \
  -e RACK_ENV=production \
  auth-service-app \
  bundle exec rails db:migrate
```

## Key Environment Variables Required

Make sure these are always set when running Rails commands:
- `RAILS_ENV=production` (or development/test)
- `RACK_ENV=production` (or development/test)
- `RAILS_LOG_TO_STDOUT=true` (for Docker logging)
- `DB_HOST=db` (for Docker Compose)
- `DB_USERNAME=auth_user` (match docker-compose.yml)
- `DB_PASSWORD=auth_password` (match docker-compose.yml)
- `DB_NAME=auth_service_development` (match docker-compose.yml)

## Verifying the Fix

### 1. Check container logs
```bash
docker logs -f auth-service-app
```
You should see:
```
✓ Database is ready!
Running database migrations...
✓ Database migrations completed successfully
```

### 2. Check database for applied migrations
```bash
docker exec -it auth-service-db mysql -u auth_user -p auth_service_development
mysql> select * from schema_migrations;
```

### 3. Run a Rails console inside the container
```bash
docker exec -it auth-service-app /bin/bash
source /app/docker/rails-cli-helper.sh
bundle exec rails console
```

## Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| `RAILS_ENV: production: command not found` | Use quotes: `export RAILS_ENV=production` |
| `Couldn't find database` | Ensure DB_HOST, DB_USERNAME, DB_PASSWORD match docker-compose.yml |
| `Rails generator only processes one at a time` | Make sure you're in `/app` directory |
| `Bundler lockfile missing` | Rebuild Docker image: `docker-compose build` |

## Testing Migrations Manually

Once the environment is set up correctly:

```bash
# List all migrations and their status
bundle exec rails db:migrate:status

# Run migrations up to a specific version
bundle exec rails db:migrate VERSION=20240101000001

# Rollback last migration
bundle exec rails db:rollback

# Run seed data
bundle exec rails db:seed
```

## Docker-Compose Quick Reference

```bash
# Rebuild and start containers
docker-compose up --build

# View logs
docker-compose logs -f app

# Run command in app container
docker-compose exec app bundle exec rails db:migrate

# Start a bash shell
docker-compose exec app /bin/bash

# Rebuild only the app image
docker-compose build app
```

## Files Modified

The following files have been updated to fix this issue:
1. **Dockerfile** - Added bundler configuration and RAILS_ROOT environment variable
2. **docker-entrypoint.sh** - Explicitly exports environment variables and validates directory setup
3. **docker-compose.yml** - Added RACK_ENV and RAILS_SERVE_STATIC_FILES
4. **docker/rails-cli-helper.sh** - New helper script for manual Rails CLI usage

## Prevention Tips

1. Always set `RAILS_ENV` before running Rails commands
2. Always run from the `/app` directory
3. Use the helper script when manually accessing the container
4. Check container logs to confirm migrations ran during startup
5. Keep Gemfile and Gemfile.lock in sync
