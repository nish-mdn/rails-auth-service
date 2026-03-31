#!/bin/bash
# Helper script to set up Rails CLI environment inside the container
# Source this script before running manual Rails commands inside the container:
#   source /app/docker/rails-cli-helper.sh

# Set Rails environment variables
export RAILS_ENV=${RAILS_ENV:-production}
export RACK_ENV=${RACK_ENV:-production}
export RAILS_LOG_TO_STDOUT=true
export RAILS_SERVE_STATIC_FILES=true

# Ensure we're in the app directory
cd /app

echo "✓ Rails CLI environment configured"
echo "  RAILS_ENV=$RAILS_ENV"
echo "  Working directory: $(pwd)"
echo ""
echo "You can now run Rails commands like:"
echo "  bundle exec rails db:migrate"
echo "  bundle exec rails db:seed"
echo "  bundle exec rails console"
