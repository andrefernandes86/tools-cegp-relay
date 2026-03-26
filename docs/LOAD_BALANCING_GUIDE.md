# Load Balancing for CEGP SMTP Relay - Complete Guide

## Table of Contents
1. [Load Balancing Overview](#load-balancing-overview)
2. [Kubernetes Service Load Balancing](#kubernetes-service-load-balancing)
3. [Advanced Load Balancing Strategies](#advanced-load-balancing-strategies)
4. [Multi-Region Load Balancing](#multi-region-load-balancing)
5. [HAProxy Configuration](#haproxy-configuration)
6. [Monitoring & Tuning](#monitoring--tuning)
7. [Troubleshooting Load Balancing](#troubleshooting-load-balancing)

---

## Load Balancing Overview

### Why Load Balancing Matters for SMTP

SMTP is a **connection-oriented protocol**, unlike HTTP which is stateless. This affects how load balancing works:

```
HTTP vs SMTP Load Balancing
═══════════════════════════════════════════════════════════

HTTP (Request-Response):
  Single request → Single response → Connection closes
  Each request can go to different server
  
  Client: "GET /api/data"
  LB routes to: Pod A
  
  Client: "GET /api/data"
  LB routes to: Pod B (different server is fine)


SMTP (Connection-Oriented):
  One connection → Multiple messages
  Once connected, all messages on same connection
  
  Client: "EHLO relay"
  LB routes to: Pod A
  
  Client: "MAIL FROM: ..." (message 1)
  Goes to: Pod A (same connection)
  
  Client: "MAIL FROM: ..." (message 2)
  Goes to: Pod A (same connection)
  
  Only when connection closes/reopens does LB choose again

Result:
  HTTP: Natural load distribution (every request balanced)
  SMTP: Connection-level load distribution (connection balanced)
```

### Types of Load Balancing

```
┌────────────────────────────────────────────────────────┐
│ LOAD BALANCING TYPES FOR SMTP RELAY                    │
├────────────────────────────────────────────────────────┤
│                                                         │
│ 1. CONNECTION-LEVEL (Kubernetes Service - Default)    │
│    - Balances at TCP connection establishment          │
│    - Each new connection may go to different pod       │
│    - CEGP keeps connection open for multiple messages  │
│    - Simple, no configuration needed                   │
│    - RECOMMENDED for most users                        │
│                                                         │
├────────────────────────────────────────────────────────┤
│                                                         │
│ 2. ROUND-ROBIN (Kubernetes Service option)            │
│    - Distributes connections in order                  │
│    - Pod 1 → Pod 2 → Pod 3 → Pod 1 → ...             │
│    - Predictable, even distribution                   │
│    - Works well for SMTP with persistent connections  │
│    - Already configured in default setup              │
│                                                         │
├────────────────────────────────────────────────────────┤
│                                                         │
│ 3. LEAST CONNECTIONS (HAProxy)                        │
│    - Sends new connection to pod with fewest conns    │
│    - Pod A: 5 connections                             │
│    - Pod B: 3 connections ← New connection goes here  │
│    - More complex to set up (requires HAProxy)        │
│    - Better for SMTP with variable connection rates   │
│                                                         │
├────────────────────────────────────────────────────────┤
│                                                         │
│ 4. RANDOM (Kubernetes Service option)                 │
│    - Randomly assigns new connections                 │
│    - Statistically even distribution                  │
│    - Simple, but unpredictable                        │
│    - Usually not needed for SMTP                      │
│                                                         │
├────────────────────────────────────────────────────────┤
│                                                         │
│ 5. STICKY SESSIONS / CLIENT-IP (Kubernetes option)   │
│    - All connections from same IP go to same pod      │
│    - CEGP IP 150.70.149.5 → Always Pod A             │
│    - Preserves message ordering                       │
│    - Can cause uneven distribution                    │
│    - Use only if ordering critical                    │
│                                                         │
├────────────────────────────────────────────────────────┤
│                                                         │
│ 6. WEIGHTED (HAProxy)                                 │
│    - Assign different weights to pods                 │
│    - Pod A: weight 3 (gets 60% of connections)       │
│    - Pod B: weight 1 (gets 20% of connections)       │
│    - Pod C: weight 1 (gets 20% of connections)       │
│    - Useful for heterogeneous hardware                │
│                                                         │
└────────────────────────────────────────────────────────┘
```

---

## Kubernetes Service Load Balancing

### Default Configuration (Recommended)

This is what's already in `kubernetes-deployment.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cegp-smtp-relay
  namespace: email-security
  labels:
    app: cegp-smtp-relay
spec:
  type: LoadBalancer                    # ← For external access
  
  # Optional: Restrict to specific IPs
  loadBalancerSourceRanges:
    - 150.70.149.0/27                   # CEGP US-East
    - 150.70.149.32/27                  # CEGP region 2
    - 150.70.236.0/24                   # CEGP region 3
    # ... add all CEGP regional IPs
  
  selector:
    app: cegp-smtp-relay
  
  ports:
    - name: smtp
      port: 25                          # External port
      targetPort: 25                    # Pod port
      protocol: TCP
  
  sessionAffinity: None                 # ← No sticky sessions
  # sessionAffinity: ClientIP           # ← Use this for ordering
  
  externalTrafficPolicy: Local          # ← Optimize routing
```

### How It Works

```
CEGP (150.70.149.5) → LoadBalancer (203.0.113.100:25)
                           ↓
                 Kubernetes Service
                           ↓
         ┌──────────────────┼──────────────────┐
         ↓                  ↓                  ↓
     Pod 1:25           Pod 2:25           Pod 3:25
    (10.0.1.5)         (10.0.1.6)         (10.0.1.7)

Kernel-Level Load Balancing (iptables rules):

On each node, Kubernetes creates iptables rules:

  -A KUBE-SVC-... -p tcp -m tcp --dport 25 \
    -j KUBE-SEP-POD1 (1/3 probability)
  
  -A KUBE-SVC-... -p tcp -m tcp --dport 25 \
    -j KUBE-SEP-POD2 (1/3 probability)
  
  -A KUBE-SVC-... -p tcp -m tcp --dport 25 \
    -j KUBE-SEP-POD3 (1/3 probability)

Result:
  Every new TCP connection:
    33% probability → Pod 1
    33% probability → Pod 2
    33% probability → Pod 3
```

### Deploy with Kubernetes Service LB

```bash
# Apply the manifest (already includes this)
kubectl apply -f kubernetes-deployment.yaml

# Get the external IP
kubectl get svc -n email-security cegp-smtp-relay

# Expected output:
# NAME               TYPE           CLUSTER-IP      EXTERNAL-IP
# cegp-smtp-relay    LoadBalancer   10.96.1.50      203.0.113.100

# Configure CEGP console with this IP: 203.0.113.100:25

# Verify it's working
kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- \
  echo "test" | nc localhost 25
```

### Benefits

✓ **Zero Configuration**: Works out of the box  
✓ **Cloud Native**: Managed by Kubernetes  
✓ **Efficient**: Kernel-level (iptables), very fast  
✓ **Scalable**: Automatically updates when pods scale  
✓ **Reliable**: Built-in health checks  
✓ **No Single Point of Failure**: Multiple control planes  

---

## Advanced Load Balancing Strategies

### Strategy 1: Round-Robin (Default)

```yaml
# This is the default, no special config needed
# Kubernetes automatically uses round-robin

sessionAffinity: None
# Connections distributed in order:
# Conn 1 → Pod 1
# Conn 2 → Pod 2
# Conn 3 → Pod 3
# Conn 4 → Pod 1
# ...
```

### Strategy 2: Client IP Affinity (Sticky Sessions)

**Use Case:** When you need to preserve message ordering from CEGP

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cegp-smtp-relay
  namespace: email-security
spec:
  type: LoadBalancer
  selector:
    app: cegp-smtp-relay
  ports:
    - name: smtp
      port: 25
      targetPort: 25
      protocol: TCP
  
  sessionAffinity: ClientIP              # ← ENABLE STICKY SESSIONS
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 3600               # ← Keep for 1 hour
```

**How It Works:**

```
CEGP IP: 150.70.149.5

First connection (14:32:00):
  150.70.149.5 → LoadBalancer → Pod 1
  Kubernetes records: 150.70.149.5 → Pod 1

Second connection (14:45:00):
  150.70.149.5 → LoadBalancer → Pod 1 (same as before)
  
Third connection (14:50:00):
  150.70.149.5 → LoadBalancer → Pod 1 (same pod)

After 3600 seconds (1 hour):
  Affinity times out
  Next connection could go to different pod

Benefits:
  ✓ Message ordering preserved
  ✓ Easier debugging (all logs from one pod)
  ✓ Reduced context switching

Drawbacks:
  ✗ Uneven load distribution (one pod gets most traffic)
  ✗ If Pod 1 goes down, affinity broken (goes to different pod)
  ✗ Not needed for most use cases
```

**Apply It:**

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: cegp-smtp-relay
  namespace: email-security
spec:
  type: LoadBalancer
  selector:
    app: cegp-smtp-relay
  ports:
    - name: smtp
      port: 25
      targetPort: 25
      protocol: TCP
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 3600
EOF
```

### Strategy 3: External Traffic Policy (Local)

**Use Case:** Preserve client IP and reduce hops

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cegp-smtp-relay
  namespace: email-security
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local          # ← ADD THIS
  selector:
    app: cegp-smtp-relay
  ports:
    - name: smtp
      port: 25
      targetPort: 25
      protocol: TCP
```

**How It Works:**

```
Without externalTrafficPolicy: Local
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CEGP (10.0.1.100) → LB (203.0.113.100:25) → Node A → Pod (on Node C)
                                              ↓
                                         Extra hop to Node C
                                         Source IP lost


With externalTrafficPolicy: Local
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CEGP (10.0.1.100) → LB (203.0.113.100:25) → Node A → Pod (on Node A)
                                           Direct delivery
                                           Source IP preserved
```

**Benefits:**

✓ Preserves client IP (CEGP's real IP)  
✓ Lower latency (no inter-node routing)  
✓ Better load distribution (uses only local pods)  
✓ Logs show real CEGP IP  

**Trade-off:**

If a node has no relay pods, connections are refused (no failover to other nodes)  
Solution: Use `pod-affinity` or ensure pods spread evenly

---

## Multi-Region Load Balancing

### Setup: Three Regions with Failover

```
Scenario:
- 3 Kubernetes clusters in different regions
- DNS-based load balancing with automatic failover
- CEGP connected to all three

┌─────────────────────────────────────────────────────────┐
│ Kubernetes Cluster - US-EAST                            │
│ Load Balancer IP: 203.0.113.10                         │
│ Service: cegp-smtp-relay (3-20 pods)                   │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Kubernetes Cluster - US-WEST                            │
│ Load Balancer IP: 198.51.100.20                        │
│ Service: cegp-smtp-relay (3-20 pods)                   │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Kubernetes Cluster - EU                                 │
│ Load Balancer IP: 192.0.2.30                           │
│ Service: cegp-smtp-relay (3-20 pods)                   │
└─────────────────────────────────────────────────────────┘
```

### DNS Configuration (Route 53 / CloudFlare)

```
DNS Records:
━━━━━━━━━━━━

relay.company.local  A   203.0.113.10    (US-EAST, priority 1)
relay.company.local  A   198.51.100.20   (US-WEST, priority 2)
relay.company.local  A   192.0.2.30      (EU, priority 3)


With GeoDNS (Location-Based Routing):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

US IP → relay.company.local → 203.0.113.10 (US-EAST, closest)
EU IP → relay.company.local → 192.0.2.30 (EU, closest)
ASIA IP → relay.company.local → 198.51.100.20 (US-WEST, next closest)


With Failover (Health Checks):
━━━━━━━━━━━━━━━━━━━━━━━━━━━

Primary: relay.company.local → 203.0.113.10 (US-EAST)
Fallback: If US-EAST down → 198.51.100.20 (US-WEST)
Final: If US-WEST down → 192.0.2.30 (EU)
```

### Implementation (Route 53 Example)

```
AWS Route 53 Configuration:

1. Create Health Checks

   Health Check 1: US-EAST
   Type: Endpoint
   Protocol: TCP
   IP: 203.0.113.10
   Port: 25
   Interval: 30 seconds
   Failure threshold: 3

   Health Check 2: US-WEST
   Type: Endpoint
   Protocol: TCP
   IP: 198.51.100.20
   Port: 25
   Interval: 30 seconds
   Failure threshold: 3

   Health Check 3: EU
   Type: Endpoint
   Protocol: TCP
   IP: 192.0.2.30
   Port: 25
   Interval: 30 seconds
   Failure threshold: 3

2. Create Weighted Routing Policy

   Record 1:
   Name: relay.company.local
   Type: A
   Value: 203.0.113.10 (US-EAST)
   Set ID: us-east
   Weight: 70              # ← 70% of traffic
   Health Check: us-east-check
   Region: US-EAST
   
   Record 2:
   Name: relay.company.local
   Type: A
   Value: 198.51.100.20 (US-WEST)
   Set ID: us-west
   Weight: 20              # ← 20% of traffic
   Health Check: us-west-check
   Region: US-WEST
   
   Record 3:
   Name: relay.company.local
   Type: A
   Value: 192.0.2.30 (EU)
   Set ID: eu
   Weight: 10              # ← 10% of traffic
   Health Check: eu-check
   Region: EU

3. Results

   Normal State:
   - 70% of CEGP queries → US-EAST (primary)
   - 20% of CEGP queries → US-WEST (secondary)
   - 10% of CEGP queries → EU (tertiary)

   If US-EAST Health Check Fails:
   - US-EAST removed from rotation
   - Remaining: 20% US-WEST, 10% EU
   - Recalculated: ~67% US-WEST, ~33% EU
   - CEGP automatically retries with new DNS

   If US-WEST Also Fails:
   - All traffic → EU (100%)
   - EU keeps system running
```

### Configuration Files

```yaml
# Kubernetes services (same in all regions)
apiVersion: v1
kind: Service
metadata:
  name: cegp-smtp-relay
  namespace: email-security
  labels:
    region: us-east         # ← Region label
spec:
  type: LoadBalancer
  selector:
    app: cegp-smtp-relay
  ports:
    - name: smtp
      port: 25
      targetPort: 25
      protocol: TCP
---
# Repeat for us-west and eu regions (change region label)
```

### Failover Behavior

```
SCENARIO: US-EAST Fails at 15:00

┌────────────────────────────────────────────────────────┐
│ Before (15:00:00)                                       │
├────────────────────────────────────────────────────────┤
│                                                         │
│ CEGP Configuration:                                    │
│   Outbound Server: relay.company.local:25              │
│                                                         │
│ DNS A Records:                                         │
│   relay.company.local → 203.0.113.10 (US-EAST)        │
│                      → 198.51.100.20 (US-WEST)         │
│                      → 192.0.2.30 (EU)                │
│                                                         │
│ Traffic Distribution:                                  │
│   70% → US-EAST (running) ✓                            │
│   20% → US-WEST (running) ✓                            │
│   10% → EU (running) ✓                                 │
│                                                         │
│ Status: All regions healthy                            │
│                                                         │
└────────────────────────────────────────────────────────┘

                         ↓ (Disaster strikes)

┌────────────────────────────────────────────────────────┐
│ During (15:00:30)                                       │
├────────────────────────────────────────────────────────┤
│                                                         │
│ Route 53 Health Check (US-EAST):                       │
│   TCP 203.0.113.10:25 → FAIL                           │
│   Retry 1: FAIL                                        │
│   Retry 2: FAIL                                        │
│   Status: UNHEALTHY                                    │
│                                                         │
│ Route 53 Updates DNS Response:                         │
│   relay.company.local → 198.51.100.20 (US-WEST)       │
│                      → 192.0.2.30 (EU)                │
│   (US-EAST removed)                                    │
│                                                         │
│ DNS TTL: 60 seconds (old CEGP DNS caches expires)     │
│                                                         │
└────────────────────────────────────────────────────────┘

                         ↓ (After TTL expires)

┌────────────────────────────────────────────────────────┐
│ After (15:01:00 +)                                      │
├────────────────────────────────────────────────────────┤
│                                                         │
│ CEGP New DNS Lookup:                                   │
│   relay.company.local → 198.51.100.20, 192.0.2.30     │
│   (Only 2 records, no US-EAST)                         │
│                                                         │
│ New Connection from CEGP:                              │
│   → Try 198.51.100.20 (US-WEST) ✓ SUCCESS             │
│                                                         │
│ Traffic Distribution (Recalculated):                   │
│   87% → US-WEST (20/(20+10) = 67%, but 100% now)      │
│   13% → EU                                             │
│                                                         │
│ Status: US-WEST and EU healthy, system running         │
│ Messages: Queued and retried, no loss                  │
│                                                         │
│ Alert Sent: US-EAST relay unavailable                  │
│                                                         │
└────────────────────────────────────────────────────────┘

                         ↓ (Recovery)

┌────────────────────────────────────────────────────────┐
│ Recovery (15:05:00)                                     │
├────────────────────────────────────────────────────────┤
│                                                         │
│ US-EAST Comes Back Online:                             │
│   Pods restart                                         │
│   Load Balancer comes up                               │
│   Service gets IP: 203.0.113.10                        │
│                                                         │
│ Route 53 Health Check:                                 │
│   TCP 203.0.113.10:25 → SUCCESS                        │
│   Status: HEALTHY                                      │
│                                                         │
│ Route 53 Adds Back to DNS:                             │
│   relay.company.local → 203.0.113.10 (US-EAST)        │
│                      → 198.51.100.20 (US-WEST)        │
│                      → 192.0.2.30 (EU)                │
│                                                         │
│ Traffic Gradually Shifts:                              │
│   70% back to US-EAST                                  │
│   20% to US-WEST                                       │
│   10% to EU                                            │
│                                                         │
│ Status: Back to normal distribution                    │
│                                                         │
└────────────────────────────────────────────────────────┘
```

---

## HAProxy Configuration

### When to Use HAProxy

```
Use Kubernetes Service LB (Default) When:
✓ Standard cloud deployment
✓ No special load balancing requirements
✓ Automatic scaling is primary need
✓ < 50k msg/min throughput

Use HAProxy When:
✓ Very high load (100k+ msg/min)
✓ Need granular control
✓ Custom algorithms (weighted, least-connections)
✓ Connection limits per backend
✓ Complex health checks
✓ On-premises, non-cloud deployment
```

### HAProxy Deployment

```yaml
# Deploy HAProxy as a pod (or external VM)
apiVersion: v1
kind: ConfigMap
metadata:
  name: haproxy-config
  namespace: email-security
data:
  haproxy.cfg: |
    global
        maxconn 100000
        tune.ssl.default-dh-param 2048
        log stdout local0
        log stdout local1 notice
    
    defaults
        log     global
        mode    tcp
        option  tcplog
        timeout connect 5000
        timeout client  50000
        timeout server  50000
    
    frontend smtp_in
        bind 0.0.0.0:25
        default_backend relay_servers
        
        # Logging
        log-format "%ci:%cp [%tr] %ft %b/%s %Tw/%Tc/%Tt %B %ts %ac %sc %rc %sq/%bq"
    
    backend relay_servers
        balance roundrobin                  # ← Load balancing algorithm
        option forwardfor
        option httpchk GET /health
        default-server inter 10s fall 3 rise 2
        
        # Pod 1
        server relay1 cegp-smtp-relay-pod1.email-security.svc.cluster.local:25 \
          check port 9090 inter 5s
        
        # Pod 2
        server relay2 cegp-smtp-relay-pod2.email-security.svc.cluster.local:25 \
          check port 9090 inter 5s
        
        # Pod 3
        server relay3 cegp-smtp-relay-pod3.email-security.svc.cluster.local:25 \
          check port 9090 inter 5s
        
        # Will auto-discover pods with label
        # See dynamic backend section below
    
    listen stats
        bind 0.0.0.0:8404
        stats enable
        stats uri /stats
        stats refresh 30s
---
apiVersion: v1
kind: Pod
metadata:
  name: haproxy-lb
  namespace: email-security
  labels:
    app: haproxy-lb
spec:
  containers:
    - name: haproxy
      image: haproxy:2.8-alpine
      ports:
        - containerPort: 25
          name: smtp
          protocol: TCP
        - containerPort: 8404
          name: stats
          protocol: TCP
      volumeMounts:
        - name: config
          mountPath: /usr/local/etc/haproxy
      resources:
        requests:
          cpu: 1000m
          memory: 512Mi
        limits:
          cpu: 2000m
          memory: 1Gi
      livenessProbe:
        tcpSocket:
          port: 25
        initialDelaySeconds: 10
        periodSeconds: 10
  
  volumes:
    - name: config
      configMap:
        name: haproxy-config
---
apiVersion: v1
kind: Service
metadata:
  name: haproxy-lb
  namespace: email-security
spec:
  type: LoadBalancer
  selector:
    app: haproxy-lb
  ports:
    - name: smtp
      port: 25
      targetPort: 25
      protocol: TCP
    - name: stats
      port: 8404
      targetPort: 8404
      protocol: TCP
```

### HAProxy Load Balancing Algorithms

```
ALGORITHM 1: Round-Robin (Default)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

balance roundrobin

Conn 1 → Pod 1
Conn 2 → Pod 2
Conn 3 → Pod 3
Conn 4 → Pod 1
Conn 5 → Pod 2
...

Use: Even distribution, good for most cases


ALGORITHM 2: Least Connections
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

balance leastconn

Pod 1: 5 connections
Pod 2: 3 connections ← New connection goes here
Pod 3: 4 connections

Use: SMTP with variable message rates


ALGORITHM 3: Source IP Hash
━━━━━━━━━━━━━━━━━━━━━━━━━

balance source

150.70.149.5 always → Pod 1
150.70.149.6 always → Pod 2
150.70.149.7 always → Pod 3

Use: Preserve ordering, sticky sessions


ALGORITHM 4: Weighted
━━━━━━━━━━━━━━━━━

server pod1 host1:25 weight 3
server pod2 host2:25 weight 1
server pod3 host3:25 weight 1

Pod 1: 60% of connections
Pod 2: 20% of connections
Pod 3: 20% of connections

Use: Heterogeneous hardware
```

### HAProxy Monitoring

```
Access HAProxy Stats Dashboard:

kubectl port-forward svc/haproxy-lb 8404:8404 -n email-security &
open http://localhost:8404/stats

Metrics Available:
  - Active connections per backend
  - Error rates
  - Response times
  - Queued requests
  - Uptime per backend

Health Check Status:
  - Each backend continuously checked via /health endpoint
  - If 3 consecutive failures: marked DOWN
  - If 2 consecutive successes: marked UP
  - Automatic enable/disable
```

---

## Monitoring & Tuning

### Load Balancing Metrics

```sql
-- Current connections per pod
SELECT pod_name, COUNT(DISTINCT connection_id) as active_connections
FROM relay_connections
WHERE status = 'active'
GROUP BY pod_name
ORDER BY active_connections DESC;

-- Messages per pod (load distribution)
SELECT pod_name, COUNT(*) as message_count
FROM relay_messages
WHERE timestamp > now() - interval '1 hour'
GROUP BY pod_name
ORDER BY message_count DESC;

-- Connection duration (persistence)
SELECT AVG(duration_seconds) as avg_connection_duration,
       MAX(messages_per_connection) as max_messages_per_conn
FROM relay_connections
WHERE timestamp > now() - interval '1 hour';

-- Pod utilization imbalance
SELECT pod_name, 
       CPU_percent,
       Memory_percent,
       message_count,
       STDDEV(message_count) OVER() as distribution_imbalance
FROM pod_metrics
WHERE timestamp > now() - interval '5 minutes'
ORDER BY message_count DESC;
```

### Tuning Load Balancing

```
1. Check Load Distribution

   kubectl top pods -n email-security
   
   Expected: Similar CPU across pods
   If Imbalanced:
     - Problem: Sticky sessions or connection pooling
     - Solution: Check if sessionAffinity enabled
     - Or: Use least-connections algorithm


2. Check Connection Count

   kubectl exec -it haproxy-lb -n email-security -- \
     netstat -an | grep ESTABLISHED | wc -l
   
   Expected: Connections evenly distributed
   High on one pod: Connection pooling is normal
   Actual SMTP connections should be ~1-5 per pod


3. Measure Latency

   kubectl logs cegp-smtp-relay-<pod> -n email-security | \
     grep delivery_latency | jq '.relay_delivery_latency_ms'
   
   Target: < 5 seconds
   If > 10 seconds: Destination unreachable or slow


4. Monitor Queue Growth

   kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- \
     postqueue -p | wc -l
   
   Normal: < 100 messages
   > 1000: Destination unreachable, need action
   > 5000: Critical, may lose messages


5. Adjust HPA Thresholds

   If scaling too aggressive:
     kubectl patch hpa cegp-smtp-relay-hpa -n email-security \
       -p '{"spec":{"metrics":[{"type":"Resource","resource":{"name":"cpu","target":{"type":"Utilization","averageUtilization":80}}}]}}'
   
   If scaling too conservative:
     kubectl patch hpa cegp-smtp-relay-hpa -n email-security \
       -p '{"spec":{"metrics":[{"type":"Resource","resource":{"name":"cpu","target":{"type":"Utilization","averageUtilization":60}}}]}}'
```

---

## Troubleshooting Load Balancing

### Issue: Uneven Load Distribution

```
Symptom:
  Pod A: 800 msg/min
  Pod B: 700 msg/min
  Pod C: 500 msg/min

Cause: Normal SMTP behavior
  CEGP maintains persistent connections
  Load distribution is at connection level, not message level
  It's OK as long as no pod is overloaded

Solution (if actually overloaded):
  Check CPU usage per pod
  If CPU < 70%: Distribution is fine
  If CPU > 80%: Scale up (add more pods)


What's Normal:
  
  With 3 pods at steady state:
    Messages may vary ±20% due to message sizes
    But CPU should be similar across all pods
    
  Example:
    Pod A: 670 msg/min, 35% CPU (normal)
    Pod B: 700 msg/min, 35% CPU (normal)
    Pod C: 630 msg/min, 35% CPU (normal)
    
  All pods' CPU same = Load balanced correctly!
```

### Issue: One Pod Gets Most Traffic

```
Symptom:
  Pod A: 1200 msg/min, 85% CPU
  Pod B: 400 msg/min, 25% CPU
  Pod C: 400 msg/min, 25% CPU

Cause: Sticky sessions enabled
  sessionAffinity: ClientIP
  All traffic from one CEGP IP → same pod

Solution:
  Option 1: Disable sticky sessions (recommended)
    kubectl patch svc cegp-smtp-relay -n email-security \
      -p '{"spec":{"sessionAffinity":"None"}}'
  
  Option 2: Keep sticky sessions but understand:
    - Message ordering preserved
    - Load imbalance is expected
    - One pod may hit limits faster
    - Need to account for this in HPA


What Happened:
  
  Without Sticky Sessions:
    Conn 1 from CEGP IP → Pod A
    Conn 2 from CEGP IP → Pod B
    Conn 3 from CEGP IP → Pod C
    Conn 4 from CEGP IP → Pod A (back to A)
    
    Result: Even distribution


  With Sticky Sessions (sessionAffinity: ClientIP):
    Conn 1 from 150.70.149.5 → Pod A (sticky)
    Conn 2 from 150.70.149.5 → Pod A (same IP)
    Conn 3 from 150.70.149.5 → Pod A (same IP)
    
    Result: All CEGP traffic to same pod
```

### Issue: LoadBalancer IP Not Assigned

```
Symptom:
  kubectl get svc -n email-security cegp-smtp-relay
  
  NAME               TYPE           CLUSTER-IP      EXTERNAL-IP
  cegp-smtp-relay    LoadBalancer   10.96.1.50      <pending>

Cause:
  - Cloud provider's LoadBalancer controller not running
  - No IP pool available
  - Quota exceeded

Solution:
  Option 1: Check LoadBalancer controller
    kubectl get svc -A | grep load-balancer-controller
    If not running, install it
  
  Option 2: Check events
    kubectl describe svc cegp-smtp-relay -n email-security
    Look for "events" section for more details
  
  Option 3: Switch to NodePort (temporary)
    kubectl patch svc cegp-smtp-relay -n email-security \
      -p '{"spec":{"type":"NodePort"}}'
    Then use node-ip:port instead of external IP
  
  Option 4: Check IP availability
    kubectl describe configmap aws-load-balancer-controller-config -A
    Verify IP pool size


Workaround (if LoadBalancer unavailable):
  
  Use ClusterIP + configure CEGP to use Kubernetes DNS:
    kubectl patch svc cegp-smtp-relay -n email-security \
      -p '{"spec":{"type":"ClusterIP"}}'
    
    Then in CEGP console:
      Server IP/FQDN: cegp-smtp-relay.email-security.svc.cluster.local
      Port: 25
```

### Issue: High Latency from One Pod

```
Symptom:
  Pod A: Avg latency 2.5s ✓
  Pod B: Avg latency 3.2s ✓
  Pod C: Avg latency 12.5s ✗

Cause:
  - Pod C on slower node
  - Pod C has memory pressure
  - Pod C's destination DNS slow
  - Network issue on Pod C's node

Solution:
  Option 1: Check pod resources
    kubectl top pod cegp-smtp-relay-pod-c -n email-security
    If high CPU/Memory: Scale up limits or add more pods
  
  Option 2: Check pod logs
    kubectl logs cegp-smtp-relay-pod-c -n email-security | tail -20
    Look for connection timeouts, DNS failures
  
  Option 3: Check node
    kubectl describe node <node-name>
    Check capacity, pressure, conditions
    If unhealthy: Drain and investigate
  
  Option 4: Manually restart pod
    kubectl delete pod cegp-smtp-relay-pod-c -n email-security
    Kubernetes will create new pod
    If latency improves: Original pod had issue


Long-Term Fix:
  - Update pod affinity to avoid specific node
  - Upgrade node hardware
  - Monitor pod performance over time
```

---

## Summary

### Load Balancing Checklist

```
☐ Service Type: LoadBalancer (external) or ClusterIP (internal)?
☐ LoadBalancer IP assigned? (kubectl get svc)
☐ CEGP configured with correct IP:port?
☐ All pods receiving traffic? (Check logs)
☐ Load distribution even? (Check CPU per pod)
☐ Sticky sessions needed? (sessionAffinity setting)
☐ Health checks working? (kubectl logs)
☐ Scaling working? (HPA active?)
☐ No single pod bottleneck? (Monitor metrics)
☐ Failover tested? (Kill a pod, check recovery)
```

### Recommended Configuration

```
For Most Users:
  type: LoadBalancer
  sessionAffinity: None
  externalTrafficPolicy: Local
  HPA: CPU 70%, Memory 75%
  Min Replicas: 3
  Max Replicas: 20

For Ordering Critical:
  type: LoadBalancer
  sessionAffinity: ClientIP (1-hour timeout)
  externalTrafficPolicy: Local
  Min Replicas: 3
  Max Replicas: 20

For Very High Load:
  Use HAProxy frontend
  algorithm: leastconn
  backend: Dynamic Kubernetes DNS service discovery
  health checks every 5 seconds
```

---

**Document Version:** 1.0  
**Last Updated:** March 2025  
**Status:** Production Ready
