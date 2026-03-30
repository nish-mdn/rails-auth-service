# 🎯 Getting Started Checklist

## Prerequisites
- [ ] Ruby 3.2+ installed (`ruby -v`)
- [ ] Rails 7.0+ installed (`rails -v`)
- [ ] MySQL 8.0+ installed and running (`mysql -u root`)
- [ ] Git installed (optional) (`git --version`)

## Initial Setup (Run Once)

### 1. Navigate to Project
```bash
cd auth-service
```
- [ ] In correct directory

### 2. Install Dependencies
```bash
bundle install
```
- [ ] All gems installed successfully
- [ ] No dependency conflicts

### 3. Configure Database
Edit `config/database.yml`:
```yaml
development:
  username: root          # <- Your MySQL username
  password: ""            # <- Your MySQL password
  host: localhost
```
- [ ] MySQL username configured
- [ ] MySQL password configured
- [ ] Database host correct (localhost for dev)

### 4. Create Databases
```bash
rails db:create
```
- [ ] Development database created
- [ ] Test database created (if applicable)

### 5. Run Migrations
```bash
rails db:migrate
```
- [ ] CreateUsers migration successful
- [ ] CreateJwtDenylists migration successful
- [ ] No migration errors

### 6. Generate RSA Keys
```bash
rails jwt:generate_keys
```
- [ ] `keys/private.pem` created
- [ ] `keys/public.pem` created
- [ ] Files are readable

### 7. Start Development Server
```bash
rails server
```
- [ ] Server starts successfully
- [ ] Listening on http://localhost:3000
- [ ] No database errors

---

## First Run Tests

### Test 1: Sign Up
```bash
curl -X POST http://localhost:3000/users \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "email": "test@example.com",
      "password": "Password123",
      "password_confirmation": "Password123"
    }
  }'
```
- [ ] Returns 201 status
- [ ] Includes JWT token in response
- [ ] User email in response matches

### Test 2: Sign In
```bash
curl -X POST http://localhost:3000/users/sign_in \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "email": "test@example.com",
      "password": "Password123"
    }
  }'
```
- [ ] Returns 200 status
- [ ] Includes JWT token in response
- [ ] Token is valid RSA256 JWT

### Test 3: Get Public Key
```bash
curl http://localhost:3000/api/v1/public_keys/show
```
- [ ] Returns 200 status
- [ ] Includes valid RSA public key
- [ ] Algorithm is RS256

### Test 4: Health Check
```bash
curl http://localhost:3000/health
```
- [ ] Returns 200 status
- [ ] Status is "ok"

---

## Common Issues Checklist

### "Database connection refused"
- [ ] MySQL is running (`mysql -u root` works)
- [ ] Username in database.yml is correct
- [ ] Password in database.yml is correct
- [ ] Host is correct (localhost for dev)

### "RSA key not found"
- [ ] `keys/` directory exists
- [ ] `keys/private.pem` exists
- [ ] `keys/public.pem` exists
- [ ] Files are readable (chmod 644/600)

### "CORS error from Main App"
- [ ] Main App domain is in `config/initializers/cors.rb`
- [ ] CORS middleware is loading
- [ ] Request has proper Origin header

### Validation errors on signup
- [ ] Email is unique (not already in database)
- [ ] Password is at least 8 characters
- [ ] Password confirmation matches password
- [ ] Email format is valid

### Token verification fails in Main App
- [ ] Getting public key with correct endpoint
- [ ] Using RS256 algorithm for verification
- [ ] Token hasn't expired (24 hour default)
- [ ] Token not in JwtDenylist (if revoked)

---

## Configuration Customization

### Change Token Expiration
Edit `config/initializers/devise.rb`:
```ruby
jwt.expiration_time = 7.days.to_i  # Change from 24.hours.to_i
```
- [ ] Updated expiration time

### Allow More CORS Origins
Edit `config/initializers/cors.rb`:
```ruby
origins 'localhost:3001', 'localhost:3002', 'yourdomain.com'
```
- [ ] Added your Main App domain(s)

### Customize Login/Signup UI
Edit:
- [ ] `app/views/devise/sessions/new.html.erb` (login form)
- [ ] `app/views/devise/registrations/new.html.erb` (signup form)

### Change Database Settings
Edit `config/database.yml`:
- [ ] Updated username
- [ ] Updated password
- [ ] Updated host/port if needed

---

## Development Workflow

### Daily Development
```bash
# Start server
rails server -p 3000

# In another terminal, work with console
rails console

# Run tests (when set up)
bundle exec rspec
```
- [ ] Rails s running on port 3000
- [ ] Console accessible
- [ ] No errors in server logs

### Database Tasks
```bash
# Create new migration
rails generate migration AddFieldToUsers

# Run migrations
rails db:migrate

# Reset database (WARNING: deletes data)
rails db:drop db:create db:migrate
```
- [ ] Migrations run cleanly
- [ ] Schema updated correctly

### Common Console Tasks
```bash
rails console

# Create user
user = User.create!(email: 'user@test.com', password: 'Pass123')

# Find user
user = User.find_by(email: 'user@test.com')

# Generate token
token = JwtService.encode({user_id: user.id, jti: user.jti})

# Verify token
decoded = JwtService.decode(token)
```
- [ ] Can create users in console
- [ ] Can generate tokens
- [ ] Can verify tokens

---

## Deployment Prep

### Before Production
- [ ] Read DEPLOYMENT.md completely
- [ ] Set up separate production database
- [ ] Generate RSA keys on production server
- [ ] Configure environment variables (.env)
- [ ] Set up HTTPS/SSL certificate
- [ ] Configure Nginx reverse proxy
- [ ] Set up database backups
- [ ] Configure monitoring/logging

### Production Checklist
- [ ] RAILS_ENV=production
- [ ] SECRET_KEY_BASE configured
- [ ] Database credentials secure
- [ ] RSA keys stored securely
- [ ] CORS origins configured properly
- [ ] Rate limiting enabled
- [ ] Security headers configured
- [ ] Monitoring active

---

## Integration with Main App

### Main App Setup
- [ ] Fetch auth service public key: `GET /api/v1/public_keys/show`
- [ ] Store JWT after login
- [ ] Include JWT in API requests: `Authorization: Bearer TOKEN`
- [ ] Verify token signature on receipt
- [ ] Handle token expiration gracefully
- [ ] Implement token refresh (optional)

---

## Documentation Review

- [ ] Read README.md (overview)
- [ ] Read QUICKSTART.md (5-minute setup)
- [ ] Read API_REFERENCE.md (API docs)
- [ ] Read DEPLOYMENT.md (production setup)
- [ ] Read BUILD_SUMMARY.md (what was created)

---

## Final Sign-Off

- [ ] Server runs without errors
- [ ] Can sign up new user
- [ ] Can sign in with correct credentials
- [ ] Can sign out
- [ ] Can get public key
- [ ] Token verification works
- [ ] Main App can integrate (if ready)
- [ ] Ready for next phase

---

## Need Help?

1. **Quick Reference**: See QUICKSTART.md
2. **API Details**: See API_REFERENCE.md
3. **Production**: See DEPLOYMENT.md
4. **Issues**: Section "Troubleshooting" in README.md

---

**Date Started**: __________  
**Date Completed**: __________  
**Team Member**: __________

---

Good luck! 🚀
