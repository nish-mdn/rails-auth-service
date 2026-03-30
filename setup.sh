#!/bin/bash

# Auth Service Setup Script
# Run this once to set up the development environment

echo "======================================"
echo "Auth Service - Development Setup"
echo "======================================"
echo ""

# Check Ruby version
echo "Checking Ruby installation..."
if ! command -v ruby &> /dev/null; then
    echo "❌ Ruby is not installed"
    echo "Install from: https://www.ruby-lang.org/en/downloads/"
    exit 1
fi

RUBY_VERSION=$(ruby -v)
echo "✓ Found: $RUBY_VERSION"
echo ""

# Check Rails
echo "Checking Rails installation..."
if ! command -v rails &> /dev/null; then
    echo "Installing Rails..."
    gem install rails
fi
echo "✓ Rails is ready"
echo ""

# Check MySQL
echo "Checking MySQL..."
if ! command -v mysql &> /dev/null; then
    echo "⚠ MySQL is not in PATH"
    echo "Install MySQL and add to PATH"
    exit 1
fi
echo "✓ MySQL is available"
echo ""

# Install dependencies
echo "Installing gem dependencies..."
bundle install
echo "✓ Gems installed"
echo ""

# Create database
echo "Creating databases..."
rails db:create
echo "✓ Databases created"
echo ""

# Run migrations
echo "Running migrations..."
rails db:migrate
echo "✓ Migrations complete"
echo ""

# Generate JWT keys
echo "Generating RSA keys for JWT..."
rails jwt:generate_keys
echo "✓ RSA keys generated"
echo ""

# Summary
echo "======================================"
echo "✓ Setup Complete!"
echo "======================================"
echo ""
echo "Next steps:"
echo "1. Start the server: rails server"
echo "2. Visit: http://localhost:3000"
echo "3. Read: QUICKSTART.md for API usage"
echo ""
echo "Create a test user:"
echo "  rails console"
echo "  User.create!(email: 'test@example.com', password: 'Password123')"
echo ""
