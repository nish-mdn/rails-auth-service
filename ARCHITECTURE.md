# Architecture & System Design

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Main App (Your Application)                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Frontend (React/Vue/etc)                                  │ │
│  │  - Store auth token in localStorage/cookie                │ │
│  │  - Include token in API requests                          │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────┬───────────────────────────────┬──────────────────┘
               │ JWT Token                     │ Public Key
               ▼                               ▼
┌──────────────────────────────────────────────────────────────────┐
│              Auth Service (This Project)                         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  API Endpoints                                           │   │
│  │  - POST /users (signup)                                 │   │
│  │  - POST /users/sign_in (login)                         │   │
│  │  - DELETE /users/sign_out (logout)                     │   │
│  │  - GET /api/v1/public_keys/show (get public key)       │   │
│  └──────────────────────────────────────────────────────────┘   │
│                         ▲                                         │
│                         │                                         │
│  ┌──────────────────────┴──────────────────────────────────┐   │
│  │              Core Services                              │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  JwtService (RSA256)                            │   │   │
│  │  │  - Sign tokens with private key                │   │   │
│  │  │  - Verify tokens with public key               │   │   │
│  │  │  - Check JTI against denylist                  │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  Devise (Authentication)                        │   │   │
│  │  │  - Password hashing (bcrypt)                    │   │   │
│  │  │  - User validation                             │   │   │
│  │  │  - Session management                          │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
│              │                          │                        │
│              ▼                          ▼                        │
│  ┌──────────────────────┐  ┌────────────────────────────┐       │
│  │  MySQL Database      │  │  RSA Key Files             │       │
│  │  ┌────────────────┐  │  │  ┌──────────────────────┐  │       │
│  │  │  users         │  │  │  │  private.pem  (600) │  │       │
│  │  │  - id (UUID)   │  │  │  │  public.pem   (644) │  │       │
│  │  │  - email       │  │  │  └──────────────────────┘  │       │
│  │  │  - password    │  │  │  (Never commit to git)     │       │
│  │  │  - jti         │  │  └────────────────────────────┘       │
│  │  └────────────────┘  │                                        │
│  │  ┌────────────────┐  │                                        │
│  │  │  jwt_denylists│  │                                        │
│  │  │  - jti         │  │                                        │
│  │  │  - exp         │  │                                        │
│  │  └────────────────┘  │                                        │
│  └──────────────────────┘                                        │
└──────────────────────────────────────────────────────────────────┘
```

---

## 🔐 Authentication Flow

### 1. User Signup
```
┌─────────────────┐
│   New User      │
└────────┬────────┘
         │
         ▼
    POST /users
    {
      email: "user@example.com",
      password: "SecurePass123",
      password_confirmation: "..."
    }
         │
         ▼
  ┌──────────────────────────────┐
  │  Devise Registration Handler │
  │  - Validate email format     │
  │  - Check email uniqueness    │
  │  - Hash password with bcrypt │
  │  - Generate UUID primary key │
  │  - Generate JWT ID (jti)     │
  └────────┬─────────────────────┘
           │
           ▼
    ┌─────────────────┐
    │  Save to MySQL  │
    └────────┬────────┘
             │
             ▼
    ┌──────────────────────────────┐
    │  JwtService.encode()         │
    │  - Create payload with jti   │
    │  - Sign with private.pem     │
    │  - Return RSA256 JWT         │
    └────────┬─────────────────────┘
             │
             ▼
    HTTP 201 Created
    {
      token: "eyJhbGciOiJSUzI1NiJ9...",
      user: {...}
    }
```

### 2. User Login
```
┌─────────────────┐
│   Existing User │
└────────┬────────┘
         │
         ▼
    POST /users/sign_in
    {
      email: "user@example.com",
      password: "SecurePass123"
    }
         │
         ▼
  ┌──────────────────────────────┐
  │  Sessions Controller          │
  │  - Find user by email         │
  │  - Verify password (bcrypt)   │
  └────────┬─────────────────────┘
           │
      ┌────┴────┐
      │          │
      ▼          ▼
   Valid    Invalid
     │          │
     ▼          ▼
Sign in   Return Error
Payload
     │
     ▼
JwtService.encode()
     │
     ▼
Return Token
```

### 3. Token Verification (Main App)
```
┌──────────────────────────┐
│  Main App               │
│  (receives token)       │
└────────┬─────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│ 1. Fetch public key                         │
│    GET /api/v1/public_keys/show            │
└────────┬────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│ 2. Verify JWT signature with public.pem    │
│    JWT.decode(token, public_key, RS256)    │
└────────┬────────────────────────────────────┘
         │
    ┌────┴────┐
    │          │
    ▼          ▼
 Valid    Invalid
   │          │
   ▼          ▼
Grant    Reject
Access   Request
```

### 4. User Logout
```
┌────────────────────┐
│  Authenticated User│
└────────┬───────────┘
         │
         ▼
    DELETE /users/sign_out
    Authorization: Bearer TOKEN
         │
         ▼
  ┌─────────────────────────────┐
  │  Sessions Controller        │
  │  1. Extract JTI from token  │
  │  2. Add JTI to denylist     │
  │  3. Sign out user session   │
  └────────┬────────────────────┘
           │
           ▼
    ┌──────────────────┐
    │  JWT Denylist    │
    │  (Store JTI)     │
    └────────┬─────────┘
             │
             ▼
    HTTP 200 OK
    {message: "Logged out"}
```

---

## 🔄 Token Lifecycle

```
┌──────────────────────────────────────────────────────────────────┐
│                        JWT Token                                 │
│  eyJhbGciOiJSUzI1NiJ9.eyJ1c2VyX2lkIjoiMTIzIiwianRpIjoiYWJjIn0...
└──────────────────────────────────────────────────────────────────┘
             │
    ┌────────┴────────┐
    │                 │
    ▼                 ▼
 HEADER         PAYLOAD             SIGNATURE
┌────────┐  ┌──────────────┐  ┌────────────────────┐
│TypAlgo │  │ user_id: 123 │  │ HMACSHA256(        │
│RS256   │  │ jti: "abc"   │  │  base64(header).   │
│        │  │ exp: 1705... │  │  base64(payload),  │
│        │  │ iat: 1705... │  │  privateKey        │
│        │  │              │  │ )                  │
└────────┘  └──────────────┘  └────────────────────┘
```

**Valid for**: 24 hours (configurable)  
**After expiration**: Must login again  
**On logout**: JTI added to denylist (instant revocation)

---

## 🛡️ Security Flow

### Password Storage
```
User Input: "SecurePass123"
    ↓
Bcrypt Hashing (10+ rounds)
    ↓
Stored: "$2a$10$hashed_value_here"

Verification:
User Input: "SecurePass123" → Compare with stored hash → Match
```

### JWT Signing
```
Payload: {user_id: "user-uuid", jti: "token-uuid"}
    ↓
Sign with Private Key (RSA 2048-bit)
    ↓
Token: eyJhbGciOiJSUzI1NiJ9...

Verification (Main App):
Token → Verify with Public Key → ✓ Valid or ✗ Invalid
```

### Token Revocation
```
Normal Logout Flow:
┌──────────────────────┐
│  Token Valid         │
│  Not in Denylist     │ → ✓ Access Granted
│  Not Expired         │
└──────────────────────┘

After Logout:
┌──────────────────────┐
│  Token Still Valid   │
│  JTI in Denylist     │ → ✗ Access Denied
│  Not Expired         │
└──────────────────────┘

After 24 Hours:
┌──────────────────────┐
│  Token Expired       │
│  (regardless of      │ → ✗ Access Denied
│   denylist)          │
└──────────────────────┘
```

---

## 🗄️ Database Relationships

```
┌─────────────────────────────┐
│         Users               │
├─────────────────────────────┤
│ id (UUID, PK)              │
│ email (unique)             │－──┐
│ encrypted_password         │   │
│ jti (unique)              │   │
│ created_at, updated_at    │   │
└─────────────────────────────┘   │
                                  │
                                  │
         ┌────────────────────────┘
         │
         │ (jti reference)
         │
         ▼
┌─────────────────────────────┐
│    JWT Denylists           │
├─────────────────────────────┤
│ id (PK)                    │
│ jti (unique) ◄─────────────│─ Links to User.jti
│ exp (expiration time)      │
│ created_at, updated_at     │
└─────────────────────────────┘

Flow:
1. User logs in → Token created with user_id + jti
2. User logs out → JTI added to jwt_denylists table
3. Next request with token → Check if JTI in denylist
4. If in denylist → Deny access (instant logout)
```

---

## 🌐 CORS & Multi-Domain Support

```
┌─────────────────────────────────────────────────────────────────┐
│                     Auth Service                                │
│  Configured Origins: ['localhost:3000', 'localhost:3001']      │
└─────────────────────────────────────────────────────────────────┘

Request from Main App (localhost:3001):
┌─────────────────────────────────────────────────────────────────┐
│ GET /api/v1/public_keys/show                                   │
│ Origin: http://localhost:3001                                  │
└─────────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────┐
│ Auth Service CORS Check                                         │
│ - Is localhost:3001 in allowed origins? YES ✓                  │
└─────────────────────────────────────────────────────────────────┘
            │
            ▼
Response + Headers:
Access-Control-Allow-Origin: http://localhost:3001
Access-Control-Allow-Methods: GET, POST, DELETE, ...
Access-Control-Allow-Credentials: true
```

---

## 📊 Request/Response Timeline

```
Time    Main App                 Network              Auth Service
──────────────────────────────────────────────────────────────────
T=0     User clicks "Sign In"
T=50    POST /users/sign_in ────────────────────→
T=55                                              Process request
T=60                                              Query database
T=65                                              Hash/verify password
T=70                                              Generate JWT
T=75    ◀────────────────────── HTTP 200 + token ◀
T=100   Store token
        (user logged in)
T=105   GET /api/data
        Header: Authorization: Bearer token ────→
T=110                                              Extract token
T=115                                              Verify signature
T=120                                              Check expiration
T=125                                              Check denylist
T=130   ◀────────────────────── HTTP 200 + data ◀
T=150   (request completed)
```

---

## 🎯 Error Handling Flow

```
Invalid Email or Password
    ↓
┌─────────────────────┐
│ Sessions Controller │
│ user&.valid... = F  │
└────────┬────────────┘
         │
         ▼
HTTP 422 Unprocessable Entity
{
  status: "unprocessable_entity",
  message: "Invalid email or password"
}
    ↓
Main App catches error
    ↓
Display to user: "Invalid email or password"
```

---

## 📈 Scaling Considerations

### Current (Single Server)
```
[Nginx] ← [Puma Workers (5)] ← [MySQL (single)]
  ↓
Token verification: Local (instant)
```

### Scaling to Multiple Servers
```
[Load Balancer]
    ↓
[Server 1: Nginx+Puma] ─┐
[Server 2: Nginx+Puma] ─┼→ [MySQL Primary]
[Server 3: Nginx+Puma] ─┘    ↓
                         [MySQL Replica 1]
                         [MySQL Replica 2]

Note: Use read replicas for public key fetches
```

---

## 🔍 Monitoring Points

```
Key Metrics to Monitor:
├── Request Latency
│   ├── /users/sign_in: Should be < 100ms
│   ├── JWT verification: Should be < 5ms
│   └── Database queries: Should be < 20ms
├── Error Rates
│   ├── 401 (invalid token): Should be < 1%
│   ├── 422 (invalid credentials): Should be < 5%
│   └── 500 (server error): Should be < 0.1%
├── Database Health
│   ├── Connection count
│   ├── Query time distribution
│   └── Denylist size growth
└── Security Events
    ├── Failed login attempts
    ├── Unusual token patterns
    └── Rate limit violations
```

---

This architecture ensures:
- ✅ **Security**: RSA256 + bcrypt + HTTPS
- ✅ **Scalability**: Stateless tokens, MySQL replication
- ✅ **Performance**: Local verification, efficient JTI checks
- ✅ **Reliability**: Denylist for instant revocation
- ✅ **Flexibility**: CORS for multiple apps
