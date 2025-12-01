# Redis Developer Connection Guide

This guide explains how to connect to Redis clusters from applications, including connection examples and best practices.

## Connection Architecture

Each Redis cluster provides **high-availability access** with automatic failover via Sentinel:

```
┌─────────────────────────────────────────────────────────────┐
│              Redis Connection Architecture                  │
│           SHARED IP - PORT-BASED ROUTING                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  External Access (Production Only)                          │
│     ├─ Shared IP: 103.110.174.22                            │
│     ├─ Ports: platform-kv:6379, cache-kv:6380               │
│     ├─ DNS: {cluster}.pnats.cloud                           │
│     └─ Features: TLS-ready, Load balanced                   │
│                                                             │
│  Internal Access (All Environments)                         │
│     ├─ Master: {cluster}.{namespace}.svc.cluster.local:6379 │
│     ├─ Replicas: {cluster}-repl.{namespace}.svc:6379        │
│     ├─ Sentinel: {cluster}-sentinel.{namespace}.svc:26379   │
│     └─ High Availability: Automatic failover via Sentinel   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Available Redis Clusters

### Production Environment

| Cluster | Purpose | External Access | Internal Access | Port |
|---------|---------|----------------|-----------------|------|
| platform-kv | Platform services, Infisical | platform-kv.pnats.cloud:6379<br/>→ 103.110.174.22:6379 | platform-kv.platform.svc:6379 | 6379 |
| cache-kv | Application caching | cache-kv.pnats.cloud:6380<br/>→ 103.110.174.22:6380 | cache-kv.platform.svc:6379 | 6380 |

**Shared IP (Port-Based Routing):**
- **Single IP**: `103.110.174.22` (all Redis clusters)
- **Efficient**: Only 1 IP used (vs 2+ with dedicated IPs)
- **Scalable**: Just assign next available port for new clusters

### Staging Environment

| Cluster | Access | Endpoint |
|---------|--------|----------|
| platform-kv | Internal only | platform-kv.platform.svc:6379 |
| cache-kv | Internal only | cache-kv.platform.svc:6379 |

### Development Environment

| Cluster | Access | Endpoint |
|---------|--------|----------|
| platform-kv | Internal only | platform-kv.platform.svc:6379 |

## Connection Types

### 1. Standard Redis Connection

**When to use:**
- Key-value operations
- Cache storage and retrieval
- Session management
- Rate limiting

**Connection:**
```bash
# Internal (from within Kubernetes)
redis-cli -h platform-kv.platform.svc -p 6379

# External (production only)
redis-cli -h platform-kv.pnats.cloud -p 6379
```

### 2. Sentinel-Aware Connection

**When to use:**
- Production applications requiring automatic failover
- High-availability requirements
- Applications that can detect master changes

**Connection:**
```bash
# Query sentinel for current master
redis-cli -h platform-kv-sentinel.platform.svc -p 26379 SENTINEL get-master-addr-by-name platform-kv-master
```

## Connection Examples

### Python (redis-py)

**Standard Connection:**
```python
import redis

# Internal connection
client = redis.Redis(
    host='platform-kv.platform.svc',
    port=6379,
    decode_responses=True
)

# External connection (production)
client = redis.Redis(
    host='platform-kv.pnats.cloud',
    port=6379,
    decode_responses=True,
    # ssl=True,  # Enable when TLS is configured
)

# Test connection
client.ping()  # Returns True
client.set('test-key', 'test-value')
value = client.get('test-key')
```

**Sentinel-Aware Connection (Recommended for HA):**
```python
from redis.sentinel import Sentinel

# Connect to sentinel cluster
sentinel = Sentinel([
    ('platform-kv-sentinel.platform.svc', 26379)
], socket_timeout=0.1)

# Get master connection
master = sentinel.master_for(
    'platform-kv-master',
    socket_timeout=0.1,
    decode_responses=True
)

# Get replica connection (read-only)
replica = sentinel.slave_for(
    'platform-kv-master',
    socket_timeout=0.1,
    decode_responses=True
)

# Use master for writes
master.set('key', 'value')

# Use replica for reads (load distribution)
value = replica.get('key')
```

### Node.js (ioredis)

**Standard Connection:**
```javascript
const Redis = require('ioredis');

// Internal connection
const redis = new Redis({
  host: 'platform-kv.platform.svc',
  port: 6379,
});

// External connection (production)
const redis = new Redis({
  host: 'platform-kv.pnats.cloud',
  port: 6379,
  // tls: {},  // Enable when TLS is configured
});

// Test connection
await redis.ping();  // Returns 'PONG'
await redis.set('test-key', 'test-value');
const value = await redis.get('test-key');
```

**Sentinel-Aware Connection (Recommended for HA):**
```javascript
const Redis = require('ioredis');

const redis = new Redis({
  sentinels: [
    { host: 'platform-kv-sentinel.platform.svc', port: 26379 }
  ],
  name: 'platform-kv-master',
  role: 'master',  // or 'slave' for read replicas
});

// Automatic failover handling
redis.on('connect', () => {
  console.log('Connected to Redis');
});

redis.on('error', (err) => {
  console.error('Redis error:', err);
});

// Use normally
await redis.set('key', 'value');
const value = await redis.get('key');
```

### Go (go-redis)

**Standard Connection:**
```go
package main

import (
    "context"
    "github.com/redis/go-redis/v9"
)

func main() {
    ctx := context.Background()
    
    // Internal connection
    client := redis.NewClient(&redis.Options{
        Addr: "platform-kv.platform.svc:6379",
    })
    
    // External connection (production)
    client := redis.NewClient(&redis.Options{
        Addr: "platform-kv.pnats.cloud:6379",
        // TLSConfig: &tls.Config{},  // Enable when TLS is configured
    })
    
    // Test connection
    pong, err := client.Ping(ctx).Result()
    client.Set(ctx, "test-key", "test-value", 0)
    val, err := client.Get(ctx, "test-key").Result()
}
```

**Sentinel-Aware Connection (Recommended for HA):**
```go
package main

import (
    "context"
    "github.com/redis/go-redis/v9"
)

func main() {
    ctx := context.Background()
    
    // Connect with sentinel
    client := redis.NewFailoverClient(&redis.FailoverOptions{
        MasterName: "platform-kv-master",
        SentinelAddrs: []string{
            "platform-kv-sentinel.platform.svc:26379",
        },
    })
    
    // Automatic failover handling
    pong, err := client.Ping(ctx).Result()
    
    // Use normally
    err = client.Set(ctx, "key", "value", 0).Err()
    val, err := client.Get(ctx, "key").Result()
}
```

### Java (Jedis)

**Standard Connection:**
```java
import redis.clients.jedis.Jedis;

public class RedisExample {
    public static void main(String[] args) {
        // Internal connection
        Jedis jedis = new Jedis("platform-kv.platform.svc", 6379);
        
        // External connection (production)
        Jedis jedis = new Jedis("platform-kv.pnats.cloud", 6379);
        // jedis.connect();  // Use SSL when TLS is configured
        
        // Test connection
        String pong = jedis.ping();
        jedis.set("test-key", "test-value");
        String value = jedis.get("test-key");
        
        jedis.close();
    }
}
```

**Sentinel-Aware Connection (Recommended for HA):**
```java
import redis.clients.jedis.JedisSentinelPool;
import redis.clients.jedis.Jedis;
import java.util.HashSet;
import java.util.Set;

public class RedisSentinelExample {
    public static void main(String[] args) {
        Set<String> sentinels = new HashSet<>();
        sentinels.add("platform-kv-sentinel.platform.svc:26379");
        
        JedisSentinelPool pool = new JedisSentinelPool(
            "platform-kv-master",
            sentinels
        );
        
        // Get connection from pool
        try (Jedis jedis = pool.getResource()) {
            jedis.set("key", "value");
            String value = jedis.get("key");
        }
        
        pool.close();
    }
}
```

### Ruby (redis-rb)

**Sentinel-Aware Connection:**
```ruby
require 'redis'

redis = Redis.new(
  url: 'redis://platform-kv-sentinel.platform.svc:26379',
  sentinels: [
    { host: 'platform-kv-sentinel.platform.svc', port: 26379 }
  ],
  role: :master,
  name: 'platform-kv-master'
)

redis.ping  # => "PONG"
redis.set('key', 'value')
value = redis.get('key')
```

### PHP (Predis)

**Sentinel-Aware Connection:**
```php
<?php
require 'vendor/autoload.php';

use Predis\Client;

$client = new Client([
    'tcp://platform-kv-sentinel.platform.svc:26379',
], [
    'replication' => 'sentinel',
    'service' => 'platform-kv-master',
]);

$client->ping();
$client->set('key', 'value');
$value = $client->get('key');
```

## Environment Variables

### Standard Configuration

```bash
# Internal access (all environments)
export REDIS_HOST=platform-kv.platform.svc
export REDIS_PORT=6379

# External access (production only)
export REDIS_HOST=platform-kv.pnats.cloud
export REDIS_PORT=6379
```

### Sentinel Configuration

```bash
# Sentinel endpoints
export REDIS_SENTINEL_HOSTS=platform-kv-sentinel.platform.svc:26379
export REDIS_SENTINEL_MASTER=platform-kv-master

# Connection settings
export REDIS_SOCKET_TIMEOUT=0.1
export REDIS_MAX_CONNECTIONS=50
```

## Getting Credentials

Redis clusters are currently configured **without authentication** for platform-internal access. For production deployments requiring authentication:

```bash
# Get password from Kubernetes secret (if configured)
kubectl get secret platform-kv-auth \
  -n platform \
  -o jsonpath='{.data.password}' | base64 -d
```

## Cluster Information

### Check Cluster Status

```bash
# Check master status
redis-cli -h platform-kv.platform.svc -p 6379 INFO replication

# Check sentinel status
redis-cli -h platform-kv-sentinel.platform.svc -p 26379 SENTINEL master platform-kv-master

# Get all sentinels
redis-cli -h platform-kv-sentinel.platform.svc -p 26379 SENTINEL sentinels platform-kv-master

# Get replicas
redis-cli -h platform-kv-sentinel.platform.svc -p 26379 SENTINEL replicas platform-kv-master
```

### Check Cluster Health

```bash
# Ping test
redis-cli -h platform-kv.platform.svc -p 6379 PING

# Get server info
redis-cli -h platform-kv.platform.svc -p 6379 INFO server

# Check memory usage
redis-cli -h platform-kv.platform.svc -p 6379 INFO memory

# Monitor commands in real-time
redis-cli -h platform-kv.platform.svc -p 6379 MONITOR
```

## Best Practices

### Connection Pooling

**Always use connection pooling** in production:

- **Python**: Use `redis.ConnectionPool`
- **Node.js**: ioredis has built-in pooling
- **Go**: Use `redis.NewClient()` (handles pooling internally)
- **Java**: Use `JedisPool` or `JedisSentinelPool`

### Error Handling

```python
from redis.exceptions import ConnectionError, TimeoutError

try:
    client.set('key', 'value')
except ConnectionError:
    # Handle connection failure
    # Sentinel will automatically failover
    pass
except TimeoutError:
    # Handle timeout
    pass
```

### Key Naming Conventions

Use namespaced keys to avoid conflicts:

```python
# Good
client.set('myapp:user:123', user_data)
client.set('myapp:session:abc', session_data)

# Bad
client.set('123', user_data)
```

### TTL Management

Set TTLs for cache entries:

```python
# Set with expiration (seconds)
client.setex('cache:result', 3600, data)

# Set with expiration (Python timedelta)
from datetime import timedelta
client.setex('cache:result', timedelta(hours=1), data)
```

## Troubleshooting

### Connection Refused

**Issue**: `ConnectionRefusedError: [Errno 111] Connection refused`

**Solutions**:
1. Check if Redis pods are running:
   ```bash
   kubectl get pods -n platform | grep platform-kv
   ```

2. Verify service exists:
   ```bash
   kubectl get svc platform-kv -n platform
   ```

3. Check network policies:
   ```bash
   kubectl get networkpolicies -n platform
   ```

### Timeout Errors

**Issue**: `TimeoutError: Timeout reading from socket`

**Solutions**:
1. Increase socket timeout in client configuration
2. Check Redis server load:
   ```bash
   redis-cli -h platform-kv.platform.svc INFO stats
   ```

3. Check network latency:
   ```bash
   kubectl exec -it platform-kv-0 -n platform -- redis-cli PING
   ```

### Sentinel Failover Issues

**Issue**: Application doesn't reconnect after failover

**Solutions**:
1. Ensure using sentinel-aware client
2. Verify sentinel quorum is healthy:
   ```bash
   redis-cli -h platform-kv-sentinel.platform.svc -p 26379 SENTINEL ckquorum platform-kv-master
   ```

3. Check sentinel logs:
   ```bash
   kubectl logs -n platform -l app.kubernetes.io/name=platform-kv-sentinel
   ```

## Monitoring

### Metrics Endpoints

Redis Exporter provides Prometheus metrics:

```
# Metrics endpoint (internal)
http://platform-kv-external.platform.svc:9121/metrics
```

### Key Metrics to Monitor

- **Memory usage**: `redis_memory_used_bytes`
- **Connected clients**: `redis_connected_clients`
- **Commands per second**: `redis_commands_processed_total`
- **Keyspace hits/misses**: `redis_keyspace_hits_total` / `redis_keyspace_misses_total`
- **Replication lag**: `redis_master_repl_offset - redis_slave_repl_offset`

## Quick Reference

| Task | Command |
|------|---------|
| Connect to Redis | `redis-cli -h platform-kv.platform.svc -p 6379` |
| Check master | `redis-cli -h platform-kv-sentinel.platform.svc -p 26379 SENTINEL get-master-addr-by-name platform-kv-master` |
| Get all keys | `redis-cli -h platform-kv.platform.svc KEYS '*'` |
| Flush cache | `redis-cli -h cache-kv.platform.svc FLUSHALL` |
| Monitor commands | `redis-cli -h platform-kv.platform.svc MONITOR` |
| Get memory info | `redis-cli -h platform-kv.platform.svc INFO memory` |

## Support

- **Template Issues**: Check `templates/*.yaml` files
- **Connection Issues**: See troubleshooting section above
- **Sentinel Issues**: Check sentinel logs
- **Platform Team**: platform-team@pnats.cloud
