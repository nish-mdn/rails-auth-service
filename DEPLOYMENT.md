# Deployment Guide

## Production Deployment

This guide covers deploying the Auth Service to a production environment.

## Pre-Deployment Checklist

- [ ] All tests passing
- [ ] Environment variables configured
- [ ] Database migrations ready
- [ ] RSA keys generated (stored securely)
- [ ] SSL/TLS certificate installed
- [ ] CORS origins configured correctly
- [ ] Rate limiting configured
- [ ] Monitoring/logging set up
- [ ] Backup strategy in place

## Environment Variables

Create a `.env.production` file with:

```env
# Rails
RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true
SECRET_KEY_BASE=<generate with: rails secret>

# Database
DB_USERNAME=auth_service_user
DB_PASSWORD=<strong_password>
DB_HOST=<production_db_host>
DB_PORT=3306

# JWT
DEVISE_JWT_SECRET_KEY=<secure_random_key>

# CORS
CORS_ALLOWED_ORIGINS=yourdomain.com,api.yourdomain.com

# Optional: Email configuration for password resets
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
```

## Database Setup

### On Production Server

```bash
# Pull latest code
git pull origin main

# Install gems
bundle install --deployment --without development test

# Create database
RAILS_ENV=production rails db:create

# Run migrations
RAILS_ENV=production rails db:migrate

# Generate RSA keys (do this once and backup securely)
RAILS_ENV=production rails jwt:generate_keys

# Precompile assets
RAILS_ENV=production rails assets:precompile
```

### Database User Privileges (MySQL)

```sql
CREATE USER 'auth_service_user'@'localhost' IDENTIFIED BY 'strong_password';

GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, 
      CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, CREATE VIEW, 
      SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, TRIGGER 
ON auth_service_production.* TO 'auth_service_user'@'localhost';

FLUSH PRIVILEGES;
```

## Web Server Configuration

### Using Puma

Update `config/puma.rb`:

```ruby
# config/puma.rb (production)
workers Integer(ENV['WEB_CONCURRENCY'] || 3)
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 16)
threads threads_count, threads_count

preload_app!

port ENV['PORT'] || 3000
environment ENV['RAILS_ENV'] || 'production'

# Socket configuration for reverse proxy
bind "unix:///tmp/puma.sock"
```

### Using Systemd

Create `/etc/systemd/system/auth-service.service`:

```ini
[Unit]
Description=Auth Service Rails App
After=network.target

[Service]
Type=simple
User=rails
WorkingDirectory=/var/www/auth-service

ExecStart=/usr/local/bin/bundle exec puma -c config/puma.rb
Restart=always
RestartSec=10

Environment="RAILS_ENV=production"
Environment="RACK_ENV=production"

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Then:
```bash
sudo systemctl daemon-reload
sudo systemctl enable auth-service
sudo systemctl start auth-service
```

## Nginx Reverse Proxy

Configure `/etc/nginx/sites-available/auth-service`:

```nginx
upstream auth_service {
  server unix:///tmp/puma.sock;
}

server {
  listen 80;
  server_name auth.yourdomain.com;
  return 301 https://$server_name$request_uri;
}

server {
  listen 443 ssl http2;
  server_name auth.yourdomain.com;

  ssl_certificate /etc/letsencrypt/live/auth.yourdomain.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/auth.yourdomain.com/privkey.pem;

  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers HIGH:!aNULL:!MD5;
  ssl_prefer_server_ciphers on;

  # Security headers
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Referrer-Policy "no-referrer-when-downgrade" always;

  # Rate limiting
  limit_req_zone $binary_remote_addr zone=auth_api:10m rate=10r/s;
  limit_req zone=auth_api burst=20 nodelay;

  client_max_body_size 4G;

  location / {
    proxy_pass http://auth_service;
    proxy_http_version 1.1;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_redirect off;

    # WebSocket support
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
```

Enable the site:
```bash
sudo ln -s /etc/nginx/sites-available/auth-service /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## SSL/TLS Certificate

Using Let's Encrypt:

```bash
sudo certbot certonly --standalone -d auth.yourdomain.com
```

Auto-renewal:
```bash
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
```

## Database Backups

### Automated Daily Backup

Create `/usr/local/bin/backup-auth-db.sh`:

```bash
#!/bin/bash

BACKUP_DIR="/var/backups/auth-service"
DATE=$(date +%Y%m%d_%H%M%S)
DB_NAME="auth_service_production"

mkdir -p $BACKUP_DIR

mysqldump -u auth_service_user -p"$DB_PASSWORD" \
  --single-transaction \
  --result-file="$BACKUP_DIR/auth_db_$DATE.sql" \
  $DB_NAME

# Keep only last 30 days
find $BACKUP_DIR -name "auth_db_*.sql" -mtime +30 -delete

# Encrypt and upload to secure storage (optional)
# gpg --encrypt --recipient your-key $BACKUP_DIR/auth_db_$DATE.sql
# aws s3 cp $BACKUP_DIR/auth_db_$DATE.sql.gpg s3://backup-bucket/
```

Create cron job:
```bash
crontab -e
# Add: 0 2 * * * /usr/local/bin/backup-auth-db.sh
```

## Monitoring & Logging

### Logrotate Configuration

Create `/etc/logrotate.d/auth-service`:

```
/var/www/auth-service/log/*.log {
  daily
  missingok
  rotate 30
  compress
  delaycompress
  notifempty
  create 0640 rails rails
  sharedscripts
  postrotate
    systemctl reload auth-service > /dev/null 2>&1 || true
  endscript
}
```

### Application Monitoring

Add to `config/environments/production.rb`:

```ruby
# Error tracking (e.g., Sentry)
require 'sentry-ruby'

Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.environment = ENV['RAILS_ENV']
  config.traces_sample_rate = 0.1
  config.release = ENV['APP_VERSION']
end
```

## Security Hardening

### File Permissions

```bash
# Restrict key permissions
chmod 600 /var/www/auth-service/keys/private.pem
chmod 644 /var/www/auth-service/keys/public.pem

# Rails directory permissions
chown -R rails:rails /var/www/auth-service
chmod -R 755 /var/www/auth-service
```

### Firewall Rules

```bash
# Allow only necessary ports
ufw allow 22/tcp  # SSH
ufw allow 80/tcp  # HTTP
ufw allow 443/tcp # HTTPS
ufw default deny incoming
ufw enable
```

### Database Security

```sql
-- Disable remote access if not needed
-- GRANT ... ON *.* TO 'auth_service_user'@'localhost' IDENTIFIED BY ...;

-- Enable query logging for audits (optional)
SET GLOBAL general_log = 'ON';
SET GLOBAL log_output = 'TABLE';
```

## Performance Optimization

### Redis Caching (Optional)

```ruby
# config/environments/production.rb
config.cache_store = :redis_cache_store, {
  url: ENV['REDIS_URL'] || "redis://localhost:6379/1",
  expires_in: 1.day
}
```

### Database Performance

```bash
# Analyze slow queries
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'test@example.com';

# Monitor with MySQL metrics
mysql -e "SHOW PROCESSLIST;" # Active queries
mysql -e "SHOW STATUS;" # Server statistics
```

## Troubleshooting Production Issues

### 500 Error Pages

Check logs:
```bash
tail -f /var/log/auth-service/production.log
journalctl -u auth-service -f
```

### Database Connection Issues

```bash
# Test connection
mysql -h db.host -u auth_service_user -p auth_service_production

# Check connection pool
rails console production
# ActiveRecord::Base.connection_pool.stat
```

### Memory Issues

```bash
# Monitor memory usage
watch -n 1 'ps aux | grep puma'

# Increase worker memory if needed
ENV['WEB_CONCURRENCY']=2  # Reduce workers
# Or increase server RAM
```

## Deployment Checklist

After deploying:

- [ ] Test signup: `curl -X POST http://localhost/users ...`
- [ ] Test login: `curl -X POST http://localhost/users/sign_in ...`
- [ ] Verify public key: `curl http://localhost/api/v1/public_keys/show`
- [ ] Check SSL: `openssl s_client -connect domain.com:443`
- [ ] Verify CORS headers are present
- [ ] Test from Main App domain
- [ ] Check logs for errors
- [ ] Monitor CPU/Memory usage
- [ ] Test database backup process

## CI/CD Pipeline Example

Using GitHub Actions, create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Run Tests
        run: |
          bundle install
          bundle exec rspec
      
      - name: Deploy
        env:
          DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}
        run: |
          mkdir -p ~/.ssh
          echo "$DEPLOY_KEY" > ~/.ssh/deploy_key
          chmod 600 ~/.ssh/deploy_key
          ssh -i ~/.ssh/deploy_key user@server 'cd /var/www/auth-service && git pull && bundle install && rails db:migrate RAILS_ENV=production && systemctl restart auth-service'
```
