# PostgreSQL Developer Connection Guide

This guide explains how to connect to PostgreSQL databases from outside the Kubernetes cluster, including proper TLS setup for secure connections.

## Connection Architecture

Each PostgreSQL cluster provides **three types of external access** via **shared IPs with different ports**:

```
┌─────────────────────────────────────────────────────────────┐
│              Connection Architecture                        │
│           SHARED IPs - PORT-BASED ROUTING                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. WRITE (Transactional - Pooled)                          │
│     ├─ DNS: {cluster}-write.pnats.cloud:{port}              │
│     ├─ Shared IP: 103.110.174.19 (ALL write endpoints)      │
│     ├─ Ports: temporal:5432, platform:5433, apps:5434       │
│     ├─ Target: Master + PgBouncer (Transaction Mode)        │
│     ├─ Use for: Application writes, transactions            │
│     └─ Features: High connection scalability                │
│                                                             │
│  2. READ (Transactional - Pooled)                           │
│     ├─ DNS: {cluster}-read.pnats.cloud:{port}               │
│     ├─ Shared IP: 103.110.174.20 (ALL read endpoints)       │
│     ├─ Ports: temporal:5432, platform:5433, apps:5434       │
│     ├─ Target: Replicas + PgBouncer (Transaction Mode)      │
│     ├─ Use for: Application reads, analytics, reporting     │
│     └─ Features: Load balanced across replicas              │
│                                                             │
│  3. ADMIN (Direct - No Pooling)                             │
│     ├─ DNS: {cluster}-admin.pnats.cloud:{port}              │
│     ├─ Shared IP: 103.110.174.21 (ALL admin endpoints)      │
│     ├─ Ports: temporal:5432, platform:5433, apps:5434       │
│     ├─ Target: Master PostgreSQL (Direct Connection)        │
│     ├─ Use for: Migrations, pg_dump, VACUUM, schema changes │
│     ├─ Features: Full PostgreSQL features                   │
│     └─ Restrictions: Office/VPN IPs only                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Available Databases

### Production Environment

| Database | Write Endpoint | Read Endpoint | Admin Endpoint | Port |
|----------|---------------|---------------|----------------|------|
| temporal-db | temporal-db-write.pnats.cloud:5432 | temporal-db-read.pnats.cloud:5432 | temporal-db-admin.pnats.cloud:5432 | 5432 |
| platform-db | platform-db-write.pnats.cloud:5433 | _(internal only)_ | platform-db-admin.pnats.cloud:5433 | 5433 |
| applications-db | applications-db-write.pnats.cloud:5434 | applications-db-read.pnats.cloud:5434 | applications-db-admin.pnats.cloud:5434 | 5434 |

**Shared IPs (Port-Based Routing):**
- **Write endpoints**: `103.110.174.19` (all databases, different ports)
- **Read endpoints**: `103.110.174.20` (all databases, different ports)
- **Admin endpoints**: `103.110.174.21` (all databases, different ports)

**Benefits:**
- Only 3 IPs used (vs 6+ with dedicated IPs)
- Efficient MetalLB IP pool utilization
- Easy to scale - just assign new port for new database

## Connection Types Explained

### 1. Write Endpoint (Transaction Mode - Pooled)

**When to use:**
- Application database connections (write operations)
- REST API backends
- Microservices
- Web applications

**How it works:**
- Connects to **PgBouncer** in transaction mode
- Routes to PostgreSQL **master** node
- Connection pooling provides high scalability
- Each transaction gets a backend connection

**Limitations:**
- ❌ No prepared statements
- ❌ No advisory locks
- ❌ No LISTEN/NOTIFY
- ❌ No session-level temporary tables
- ✅ Perfect for most application workloads

**Connection string:**
```bash
postgresql://username:password@temporal-db-write.pnats.cloud:5432/database?sslmode=verify-full
```

### 2. Read Endpoint (Transaction Mode - Pooled)

**When to use:**
- Read-only application queries
- Analytics and reporting
- Dashboard data fetching
- Read replicas for scaling reads

**How it works:**
- Connects to **PgBouncer** in transaction mode
- Routes to PostgreSQL **replica** nodes (load balanced)
- Same pooling benefits as write endpoint
- Reduces load on master

**Limitations:**
- Same as write endpoint
- ⚠️ Read-only (write attempts will fail)
- May have slight replication lag (~100ms typically)

**Connection string:**
```bash
postgresql://username:password@temporal-db-read.pnats.cloud:5432/database?sslmode=verify-full
```

### 3. Admin Endpoint (Direct - No Pooling)

**When to use:**
- Database migrations (Flyway, Liquibase, Alembic)
- Schema changes (DDL operations)
- Database maintenance (VACUUM, ANALYZE, REINDEX)
- Backups and restores (pg_dump, pg_restore)
- Administrative tasks requiring full PostgreSQL features

**How it works:**
- **Direct connection** to PostgreSQL master
- NO connection pooling
- Full PostgreSQL protocol support
- Each connection uses a real backend process

**Features:**
- ✅ Prepared statements
- ✅ Advisory locks
- ✅ LISTEN/NOTIFY
- ✅ Session variables
- ✅ Temporary tables
- ✅ All PostgreSQL features

**Security:**
- 🔒 Restricted to office/VPN IPs only
- Requires explicit IP allowlisting

**Connection string:**
```bash
postgresql://username:password@temporal-db-admin.pnats.cloud:5432/database?sslmode=verify-full
```

## TLS/SSL Configuration

All connections **require TLS encryption** using Let's Encrypt certificates.

### Get CA Certificate

```bash
# Download Let's Encrypt root CA
curl -o letsencrypt-root-ca.pem https://letsencrypt.org/certs/isrgrootx1.pem

# Or use system CA bundle (recommended)
# Most systems have Let's Encrypt CA pre-installed
```

### Connection Modes

| SSL Mode | Description | Server Auth | Certificate Required |
|----------|-------------|-------------|---------------------|
| `disable` | ❌ No encryption | No | No |
| `allow` | ❌ Encrypt if server supports | No | No |
| `prefer` | ⚠️ Encrypt if possible | No | No |
| `require` | ✅ Always encrypt | **No verification** | No |
| `verify-ca` | ✅ Encrypt + verify CA | Yes (CA) | Yes (CA cert) |
| `verify-full` | ✅ Encrypt + verify hostname | Yes (Full) | Yes (CA cert) |

**Recommended:** `sslmode=verify-full` (most secure)

## Connection Examples

### Python (psycopg2)

**Application Connection (Write):**
```python
import psycopg2

# For applications - use write endpoint with pooling
conn = psycopg2.connect(
    host="temporal-db-write.pnats.cloud",
    port=5432,
    database="temporal",
    user="temporal",
    password=os.environ["DB_PASSWORD"],
    sslmode="verify-full",
    # System CA bundle (Let's Encrypt included)
    sslrootcert="/etc/ssl/certs/ca-certificates.crt"  # Linux
    # sslrootcert="/etc/pki/tls/certs/ca-bundle.crt"  # RHEL/CentOS
    # sslrootcert="/usr/local/etc/openssl/cert.pem"   # macOS
)
```

**Migration Connection (Admin):**
```python
# For migrations - use admin endpoint (direct connection)
conn = psycopg2.connect(
    host="temporal-db-admin.pnats.cloud",
    port=5432,
    database="temporal",
    user="platform_admin",  # Admin user
    password=os.environ["ADMIN_PASSWORD"],
    sslmode="verify-full",
    sslrootcert="/etc/ssl/certs/ca-certificates.crt"
)
```

### PostgreSQL psql

**Application Query:**
```bash
# Read-only queries
psql "postgresql://temporal:${PASSWORD}@temporal-db-read.pnats.cloud:5432/temporal?sslmode=verify-full"
```

**Database Migration:**
```bash
# For migrations - use admin endpoint
psql "postgresql://platform_admin:${ADMIN_PASSWORD}@temporal-db-admin.pnats.cloud:5432/temporal?sslmode=verify-full"
```

### Java (JDBC)

**Application Connection:**
```java
String url = "jdbc:postgresql://temporal-db-write.pnats.cloud:5432/temporal"
    + "?ssl=true&sslmode=verify-full";
Connection conn = DriverManager.getConnection(url, "temporal", password);
```

**Migration Connection (Flyway):**
```java
// flyway.conf or application.properties
flyway.url=jdbc:postgresql://temporal-db-admin.pnats.cloud:5432/temporal?ssl=true&sslmode=verify-full
flyway.user=platform_admin
flyway.password=${ADMIN_PASSWORD}
```

### Node.js (pg)

**Application Connection:**
```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: 'temporal-db-write.pnats.cloud',
  port: 5432,
  database: 'temporal',
  user: 'temporal',
  password: process.env.DB_PASSWORD,
  ssl: {
    rejectUnauthorized: true, // verify-full
    ca: fs.readFileSync('/etc/ssl/certs/ca-certificates.crt').toString()
  }
});
```

### Go (lib/pq)

**Application Connection:**
```go
import (
    "database/sql"
    _ "github.com/lib/pq"
)

connStr := "host=temporal-db-write.pnats.cloud " +
    "port=5432 user=temporal password=" + password + " " +
    "dbname=temporal sslmode=verify-full " +
    "sslrootcert=/etc/ssl/certs/ca-certificates.crt"

db, err := sql.Open("postgres", connStr)
```

### Ruby (pg)

**Application Connection:**
```ruby
require 'pg'

conn = PG.connect(
  host: 'temporal-db-write.pnats.cloud',
  port: 5432,
  dbname: 'temporal',
  user: 'temporal',
  password: ENV['DB_PASSWORD'],
  sslmode: 'verify-full',
  sslrootcert: '/etc/ssl/certs/ca-certificates.crt'
)
```

## Migration Tools

### Flyway (Java)

```properties
# flyway.conf
flyway.url=jdbc:postgresql://temporal-db-admin.pnats.cloud:5432/temporal?ssl=true&sslmode=verify-full
flyway.user=platform_admin
flyway.password=${FLYWAY_PASSWORD}
flyway.locations=filesystem:./migrations
```

```bash
flyway migrate
```

### Liquibase (Java/Groovy)

```yaml
# liquibase.properties
url: jdbc:postgresql://temporal-db-admin.pnats.cloud:5432/temporal?ssl=true&sslmode=verify-full
username: platform_admin
password: ${LIQUIBASE_PASSWORD}
changeLogFile: db/changelog/db.changelog-master.xml
```

```bash
liquibase update
```

### Alembic (Python)

```python
# alembic.ini
[alembic]
sqlalchemy.url = postgresql://platform_admin:${ALEMBIC_PASSWORD}@temporal-db-admin.pnats.cloud:5432/temporal?sslmode=verify-full
```

```bash
alembic upgrade head
```

### golang-migrate

```bash
migrate -path ./migrations \
  -database "postgresql://platform_admin:${PASSWORD}@temporal-db-admin.pnats.cloud:5432/temporal?sslmode=verify-full" \
  up
```

## Credentials Management

### For Applications

**Option 1: Environment Variables (Recommended)**
```bash
export DB_HOST=temporal-db-write.pnats.cloud
export DB_PORT=5432
export DB_NAME=temporal
export DB_USER=temporal
export DB_PASSWORD=xxx  # From secrets management
```

**Option 2: Connection String**
```bash
export DATABASE_URL="postgresql://temporal:xxx@temporal-db-write.pnats.cloud:5432/temporal?sslmode=verify-full"
```

### For Migrations/Admin

```bash
export ADMIN_DB_HOST=temporal-db-admin.pnats.cloud
export ADMIN_DB_USER=platform_admin
export ADMIN_DB_PASSWORD=xxx  # From secure vault
```

### Getting Passwords

**From Kubernetes (if you have access):**
```bash
# Application user password
kubectl get secret temporal.temporal-db.credentials.postgresql.acid.zalan.do \
  -n temporal \
  -o jsonpath='{.data.password}' | base64 -d

# Platform admin password
kubectl get secret platform-admin.temporal-db.credentials.postgresql.acid.zalan.do \
  -n temporal \
  -o jsonpath='{.data.password}' | base64 -d
```

**From HashiCorp Vault (recommended for production):**
```bash
vault kv get -field=password database/temporal-db/temporal
vault kv get -field=password database/temporal-db/platform_admin
```

## Connection Patterns

### Pattern 1: Application (Read/Write Split)

```python
from psycopg2.pool import SimpleConnectionPool

# Write pool - master
write_pool = SimpleConnectionPool(
    minconn=1, maxconn=20,
    host="temporal-db-write.pnats.cloud",
    port=5432, database="temporal",
    user="temporal", password=password,
    sslmode="verify-full"
)

# Read pool - replicas
read_pool = SimpleConnectionPool(
    minconn=5, maxconn=50,
    host="temporal-db-read.pnats.cloud",
    port=5432, database="temporal",
    user="temporal", password=password,
    sslmode="verify-full"
)

# Use write pool for writes
with write_pool.getconn() as conn:
    cursor = conn.cursor()
    cursor.execute("INSERT INTO users ...")
    conn.commit()

# Use read pool for reads
with read_pool.getconn() as conn:
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users ...")
```

### Pattern 2: Migration Script

```python
import psycopg2
import sys

# Always use admin endpoint for migrations
conn = psycopg2.connect(
    host="temporal-db-admin.pnats.cloud",
    user="platform_admin",
    password=sys.argv[1],
    database="temporal",
    sslmode="verify-full"
)

# Can use all PostgreSQL features
with conn.cursor() as cur:
    # Prepared statements work
    cur.execute("PREPARE myplan AS SELECT * FROM users WHERE id = $1")

    # Advisory locks work
    cur.execute("SELECT pg_advisory_lock(123)")

    # Schema changes
    cur.execute("ALTER TABLE users ADD COLUMN email VARCHAR(255)")

conn.commit()
```

## Troubleshooting

### Connection Refused

**Check DNS resolution:**
```bash
nslookup temporal-db-write.pnats.cloud
# Should resolve to 103.110.174.19
```

**Check connectivity:**
```bash
telnet temporal-db-write.pnats.cloud 5432
# Should connect
```

**Check IP allowlist:**
```bash
curl ifconfig.me
# Your IP should be in allowedSourceRanges
```

### SSL/TLS Errors

**Error: `certificate verify failed`**

**Solution 1:** Use system CA bundle
```bash
# Linux
export PGSSLROOTCERT=/etc/ssl/certs/ca-certificates.crt

# macOS
export PGSSLROOTCERT=/usr/local/etc/openssl/cert.pem
```

**Solution 2:** Download Let's Encrypt root CA
```bash
curl -o ~/letsencrypt-ca.pem https://letsencrypt.org/certs/isrgrootx1.pem
export PGSSLROOTCERT=~/letsencrypt-ca.pem
```

**Error: `hostname mismatch`**

Ensure you're using the correct hostname:
- ✅ `temporal-db-write.pnats.cloud`
- ❌ `103.110.174.19` (IP won't match certificate)

### Pooler Limitations

**Error: `prepared statement does not exist`**

You're using a pooled endpoint (write/read) with prepared statements.

**Solution:** Use admin endpoint for migrations:
```python
# Change from:
host="temporal-db-write.pnats.cloud"  # Pooled

# To:
host="temporal-db-admin.pnats.cloud"  # Direct
```

### Access Denied

**Error: `no pg_hba.conf entry for host`**

Your IP is not in the allowlist.

**Check your IP:**
```bash
curl ifconfig.me
```

**Request allowlist update:** Contact platform team to add your IP.

## Best Practices

### 1. Use Appropriate Endpoints

- ✅ Applications → Write/Read endpoints (pooled)
- ✅ Migrations → Admin endpoint (direct)
- ❌ Don't use admin for application traffic (wastes connections)
- ❌ Don't use pooled endpoints for migrations (features missing)

### 2. Always Use TLS

- ✅ `sslmode=verify-full` (recommended)
- ✅ `sslmode=require` (minimum)
- ❌ Never use `sslmode=disable` in production

### 3. Connection Pooling

- Application pools connect to write/read endpoints (already pooled)
- Keep application pool size moderate (10-50 connections)
- PgBouncer handles backend pooling

### 4. Read/Write Splitting

- Route heavy reads to read endpoint (replicas)
- Keep writes on write endpoint (master)
- Accept potential replication lag on read endpoint

### 5. Credentials Security

- Never hardcode passwords
- Use environment variables or secrets management
- Rotate credentials periodically
- Use different credentials for different environments

### 6. IP Allowlisting

- Always restrict admin endpoint to known IPs
- Use VPN for remote developer access
- Keep allowlist minimal

## Environment-Specific Connections

### Development

```bash
# Local development against production (read-only)
export DATABASE_URL="postgresql://temporal:${PASSWORD}@temporal-db-read.pnats.cloud:5432/temporal?sslmode=verify-full"
```

### Staging

```bash
# Staging typically uses different databases (not covered in this guide)
```

### Production

```bash
# Production applications
export DB_WRITE_URL="postgresql://temporal:${PASSWORD}@temporal-db-write.pnats.cloud:5432/temporal?sslmode=verify-full"
export DB_READ_URL="postgresql://temporal:${PASSWORD}@temporal-db-read.pnats.cloud:5432/temporal?sslmode=verify-full"
```

## Support

For access issues or questions:
- **Platform Team**: platform-team@pnats.cloud
- **Documentation**: [Internal Wiki](https://wiki.pnats.cloud)
- **IP Allowlist Requests**: Create ticket in JIRA

## Quick Reference

| Endpoint | DNS | Port | Pool | Use Case |
|----------|-----|------|------|----------|
| Write | {cluster}-write.pnats.cloud | 5432 | Yes (Transaction) | App writes |
| Read | {cluster}-read.pnats.cloud | 5432 | Yes (Transaction) | App reads |
| Admin | {cluster}-admin.pnats.cloud | 5432 | No (Direct) | Migrations |
