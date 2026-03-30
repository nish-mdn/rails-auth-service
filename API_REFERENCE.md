# API Reference Guide

## Base URL
```
http://localhost:3000
```

## Authentication Endpoints

### 1. User Registration (Sign Up)

**Endpoint:** `POST /users`

**Headers:**
```
Content-Type: application/json
X-CSRF-Token: [from page meta tag]
```

**Request Body:**
```json
{
  "user": {
    "email": "newuser@example.com",
    "password": "SecurePass123",
    "password_confirmation": "SecurePass123"
  }
}
```

**Success Response (201 Created):**
```json
{
  "status": "created",
  "message": "Account created successfully",
  "token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "newuser@example.com",
    "created_at": "2024-01-15T10:30:00Z",
    "updated_at": "2024-01-15T10:30:00Z"
  }
}
```

**Error Response (422 Unprocessable Entity):**
```json
{
  "status": "unprocessable_entity",
  "errors": [
    "Email has already been taken",
    "Password is too short (minimum is 8 characters)"
  ]
}
```

---

### 2. User Login (Sign In)

**Endpoint:** `POST /users/sign_in`

**Headers:**
```
Content-Type: application/json
X-CSRF-Token: [from page meta tag]
```

**Request Body:**
```json
{
  "user": {
    "email": "user@example.com",
    "password": "SecurePass123"
  }
}
```

**Success Response (200 OK):**
```json
{
  "status": "ok",
  "message": "Logged in successfully",
  "token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "created_at": "2024-01-15T09:00:00Z",
    "updated_at": "2024-01-15T10:30:00Z"
  }
}
```

**Error Response (422 Unprocessable Entity):**
```json
{
  "status": "unprocessable_entity",
  "message": "Invalid email or password"
}
```

---

### 3. User Logout (Sign Out)

**Endpoint:** `DELETE /users/sign_out`

**Headers:**
```
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
X-CSRF-Token: [from page meta tag]
```

**Success Response (200 OK):**
```json
{
  "status": "ok",
  "message": "Logged out successfully"
}
```

---

## Security & Key Management

### 4. Get Public Key (for JWT Verification)

**Endpoint:** `GET /api/v1/public_keys/show`

**Headers:**
```
Accept: application/json
```

**Success Response (200 OK):**
```json
{
  "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2Z...\n-----END PUBLIC KEY-----\n",
  "algorithm": "RS256"
}
```

---

## Health & Status

### 5. Health Check

**Endpoint:** `GET /health`

**Success Response (200 OK):**
```json
{
  "status": "ok"
}
```

---

### 6. Service Status

**Endpoint:** `GET /`

**Success Response (200 OK):**
```json
{
  "message": "Auth Service is running",
  "version": "1.0.0"
}
```

---

## JWT Token Usage

Tokens received from login/signup should be stored securely (e.g., in httpOnly cookies or localStorage).

Include the token in requests to protected endpoints:

```javascript
// JavaScript Example
const token = localStorage.getItem('authToken');
const response = await fetch('/protected-endpoint', {
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  }
});
```

```bash
# cURL Example
curl -H "Authorization: Bearer TOKEN_HERE" \
  -H "Content-Type: application/json" \
  http://localhost:3000/protected-endpoint
```

---

## Token Claims

The JWT payload contains:

```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "jti": "unique-jwt-id",
  "exp": 1705315800,
  "iat": 1705229400
}
```

- **user_id**: Unique identifier of the authenticated user
- **jti**: JWT ID (used for token revocation)
- **exp**: Token expiration time (Unix timestamp)
- **iat**: Issued at time (Unix timestamp)

---

## Error Handling

All errors return appropriate HTTP status codes:

- **200 OK** - Request succeeded
- **201 Created** - Resource created successfully
- **400 Bad Request** - Invalid request format
- **401 Unauthorized** - Missing or invalid authentication
- **422 Unprocessable Entity** - Validation failed
- **500 Internal Server Error** - Server error

---

## CORS Considerations

This service returns CORS headers enabling requests from:
- `localhost:3000` - 3001, 3002, etc.
- Configured domains in `config/initializers/cors.rb`

---

## Rate Limiting

Currently unrestricted. Consider implementing rate limiting in production.

---

## Security Notes

1. **Always use HTTPS** in production
2. **Store tokens securely** (httpOnly cookies recommended)
3. **Token expiry** is 24 hours by default
4. **Never expose private keys**
5. **Validate token signature** using the public key
6. **Check token expiration** before using
7. **Handle revoked tokens** (check jti against denylist)

---

## Integration Example (Node.js)

```javascript
const axios = require('axios');

const api = axios.create({
  baseURL: 'http://localhost:3000',
  headers: {
    'Content-Type': 'application/json'
  }
});

// Sign up
async function signup(email, password) {
  const response = await api.post('/users', {
    user: {
      email,
      password,
      password_confirmation: password
    }
  });
  return response.data.token;
}

// Sign in
async function login(email, password) {
  const response = await api.post('/users/sign_in', {
    user: { email, password }
  });
  return response.data.token;
}

// Use authenticated requests
async function authenticatedRequest(token) {
  const headers = { Authorization: `Bearer ${token}` };
  const response = await api.get('/protected-endpoint', { headers });
  return response.data;
}

// Sign out
async function logout(token) {
  const headers = { Authorization: `Bearer ${token}` };
  await api.delete('/users/sign_out', { headers });
}

// Get public key for verification (in your main app)
async function getPublicKey() {
  const response = await api.get('/api/v1/public_keys/show');
  return response.data.public_key;
}
```

---

## Testing with cURL

```bash
# Sign up
curl -X POST http://localhost:3000/users \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "email": "test@example.com",
      "password": "Password123",
      "password_confirmation": "Password123"
    }
  }'

# Sign in
curl -X POST http://localhost:3000/users/sign_in \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "email": "test@example.com",
      "password": "Password123"
    }
  }'

# Get public key
curl -X GET http://localhost:3000/api/v1/public_keys/show

# Sign out
curl -X DELETE http://localhost:3000/users/sign_out \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```
