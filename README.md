# Auth Service - Central Identity Provider

A standalone Ruby on Rails Authentication Service that acts as a Central Identity Provider for separate applications. Uses JWT with RSA256 asymmetric encryption for secure token-based authentication.

## Features

- **MySQL Database** with UUID primary keys for enhanced security
- **Devise Integration** for standard authentication mechanisms
- **JWT Authentication** with RSA256 asymmetric encryption
- **Token Revocation** via JWT denylist for instant logout
- **CORS Support** for multi-domain/port applications
- **Clean UI** with Tailwind CSS for Login/Signup flows
- **Public Key Endpoint** for external service token verification

## Prerequisites

- Ruby 3.2.0
- Rails 7.0+
- MySQL 8.0+
- Node.js (for asset compilation)

## Installation

1. **Clone and Setup**
   ```bash
   cd auth-service
   bundle install
   ```

2. **Configure Database**
   Update `config/database.yml` with your MySQL credentials:
   ```yaml
   development:
     adapter: mysql2
     database: auth_service_development
     username: root
     password: ""
     host: localhost
   ```

3. **Create and Migrate Database**
   ```bash
   rails db:create
   rails db:migrate
   ```

4. **Generate RSA Keys**
   ```bash
   rails jwt:generate_keys
   ```
   This creates `keys/private.pem` and `keys/public.pem`

5. **Start the Server**
   ```bash
   rails server -p 3000
   ```

## API Endpoints

### Authentication

- **Sign Up**
  ```
  POST /users
  Content-Type: application/json
  
  {
    "user": {
      "email": "user@example.com",
      "password": "password123",
      "password_confirmation": "password123"
    }
  }
  ```

- **Sign In**
  ```
  POST /users/sign_in
  Content-Type: application/json
  
  {
    "user": {
      "email": "user@example.com",
      "password": "password123"
    }
  }
  ```
  
  Response:
  ```json
  {
    "status": "ok",
    "message": "Logged in successfully",
    "token": "eyJhbGciOiJSUzI1NiJ9...",
    "user": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "email": "user@example.com",
      "created_at": "2024-01-01T00:00:00Z",
      "updated_at": "2024-01-01T00:00:00Z"
    }
  }
  ```

- **Sign Out**
  ```
  DELETE /users/sign_out
  Authorization: Bearer <token>
  ```

### Public Key Access

- **Get Public Key** (for JWT verification)
  ```
  GET /api/v1/public_keys/show
  ```
  
  Response:
  ```json
  {
    "public_key": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----\n",
    "algorithm": "RS256"
  }
  ```

## JWT Token Usage

Tokens are returned in the `Authorization` header. Include them in requests:

```bash
curl -H "Authorization: Bearer YOUR_TOKEN_HERE" http://localhost:3000/protected-endpoint
```

## Configuration

### CORS Settings
Edit `config/initializers/cors.rb` to allow your Main App:

```ruby
allow do
  origins 'localhost:3001', 'myapp.com'
  resource '*',
    headers: :any,
    methods: [:get, :post, :put, :patch, :delete, :options],
    credentials: true
end
```

### Environment Variables
Create a `.env` file:

```env
DB_USERNAME=root
DB_PASSWORD=password
DB_HOST=localhost
DB_PORT=3306
DEVISE_JWT_SECRET_KEY=your_secret_key_here
CORS_ALLOWED_ORIGINS=localhost:3001,localhost:3002
```

## Database Schema

### Users Table
- `id` (VARCHAR(36)) - UUID Primary Key
- `email` (VARCHAR(255)) - Unique
- `encrypted_password` (VARCHAR(255)) - Devise hash
- `jti` (VARCHAR(255)) - JWT Identifier for revocation
- `created_at`, `updated_at` - Timestamps

### JWT Denylists Table
- `id` (INTEGER) - Primary Key
- `jti` (VARCHAR(255)) - Revoked token identifier
- `created_at`, `updated_at` - Timestamps

## Security Considerations

1. **RSA Keys**: Keep `keys/private.pem` secure and never expose it
2. **Public Key**: The public key is safe to share with other services
3. **Token Expiry**: Tokens expire after 24 hours (configurable in ENV)
4. **Database Security**: Use strong MySQL passwords in production
5. **HTTPS**: Always use HTTPS in production

## Testing

```bash
# Run all tests
bundle exec rspec

# Run specific test
bundle exec rspec spec/models/user_spec.rb
```

## Troubleshooting

**Database Connection Error**
- Ensure MySQL is running
- Check credentials in `config/database.yml`

**JWT Key Not Found**
- Run `rails jwt:generate_keys` to create RSA keys
- Check that `keys/` directory exists and is readable

**CORS Errors**
- Verify the origin of the requesting app in `config/initializers/cors.rb`
- Check that credentials are allowed if needed

## Integration with Main App

To verify JWTs in your Main App:

```ruby
# In your Main App's auth middleware
require 'net/http'

class JwtVerifier
  def initialize(token)
    @token = token
  end

  def verify
    public_key_response = Net::HTTP.get('localhost:3000', '/api/v1/public_keys/show')
    public_key = JSON.parse(public_key_response)['public_key']
    
    JWT.decode(@token, OpenSSL::PKey::RSA.new(public_key), true, algorithm: 'RS256')
  end
end
```

## License

MIT
