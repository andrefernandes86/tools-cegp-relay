# CEGP SMTP Relay Container - Complete Introduction & User Guide

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [What This Application Does](#what-this-application-does)
3. [How It Works - Step by Step](#how-it-works-step-by-step)
4. [Architecture Overview](#architecture-overview)
5. [Key Features & Benefits](#key-features--benefits)
6. [Deployment Models](#deployment-models)
7. [Message Lifecycle](#message-lifecycle)
8. [Monitoring & Management](#monitoring--management)
9. [Load Balancing](#load-balancing)
10. [Troubleshooting](#troubleshooting)

---

## Executive Summary

The **CEGP SMTP Relay Container** is a cloud-native email relay service that sits between Trend Micro's Cloud Email Gateway Protection (CEGP) and your internal mail servers. It acts as a "middleman" that:

- **Receives** scanned emails from CEGP
- **Validates** sender domains and rate limits
- **Forwards** emails to your final mail servers
- **Auto-scales** to handle traffic spikes
- **Never loses** messages (queues locally if destination is down)

**In one sentence:** A Kubernetes-native SMTP relay that ensures your emails make it safely from CEGP to your recipients without bottlenecks or failures.

---

## What This Application Does

### The Problem It Solves

```
WITHOUT Relay Container:
═══════════════════════

Customer Mail Server
        ↓ (SMTP)
    CEGP Cloud
        ↓ (SMTP)
    Direct to Destination
        
Issues:
✗ No local queue (messages lost if destination down)
✗ No rate limiting at local level
✗ CEGP must handle all delivery complexity
✗ No email continuity during CEGP outage
✗ Difficult to integrate with on-premises systems


WITH Relay Container (This Solution):
════════════════════════════════════

Customer Mail Server
        ↓ (SMTP)
    CEGP Cloud
        ↓ (SMTP)
    Relay Container (LOCAL) ← NEW
        ↓ (SMTP)
    Destination Mail Server

Benefits:
✓ Local queue ensures no message loss
✓ Rate limiting protects both sides
✓ Email continuity even if CEGP is down
✓ Auto-scaling handles traffic spikes
✓ Complete visibility & audit trail
✓ Simple integration point for customers
```

### What Problems Does It Address?

| Problem | Solution |
|---------|----------|
| **Message Loss** | Local queue in `/var/spool/postfix/` holds messages until destination accepts |
| **No Rate Limiting** | Token bucket algorithm limits 2,000 msg/min per CEGP IP, 200/min per recipient |
| **Capacity Issues** | Auto-scales from 3 to 20 pods when CPU/memory threshold hit |
| **Single Point of Failure** | 3+ replicas across nodes with pod anti-affinity |
| **No Visibility** | Prometheus metrics + structured JSON logging for every message |
| **Destination Unreachable** | Automatic retry with exponential backoff (RFC 5321 compliant) |
| **Unauthorized Access** | IP whitelist (permit-ips.conf) + domain whitelist (domains.conf) |
| **Configuration Drift** | ConfigMaps allow hot-reload without pod restart |

---

## How It Works - Step by Step

### Phase 1: Setup (One-Time Configuration)

```
┌─────────────────────────────────────────────────────────────┐
│ STEP 1: Deploy Relay Container to Kubernetes               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ kubectl apply -f kubernetes-deployment.yaml                 │
│                                                              │
│ Result: 3 relay pods running in Kubernetes cluster          │
│         listening on port 25 (SMTP)                         │
│                                                              │
└──────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ STEP 2: Configure Relay Policies (Your Domains)            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ kubectl patch configmap relay-policy \                      │
│   --type merge -p '{"data":{                                │
│     "domains.conf":"company.com\nsubsidiary.org"}}'         │
│                                                              │
│ Result: Relay will only accept emails from these domains   │
│                                                              │
└──────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ STEP 3: Configure CEGP IP Authorization                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ kubectl patch configmap relay-policy \                      │
│   --type merge -p '{"data":{                                │
│     "permit-ips.conf":"150.70.149.0/27\n150.70.149.32/27"}}'│
│                                                              │
│ Result: Only CEGP's regional IPs can connect to relay       │
│                                                              │
└──────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ STEP 4: Configure CEGP Console (Trend Micro Side)          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ 1. Add Domain: company.com                                  │
│ 2. Select Outbound: "User-defined mail servers"            │
│ 3. Configure Server: IP/FQDN of relay, Port 25             │
│ 4. Send test message (should arrive)                        │
│                                                              │
│ Result: CEGP knows where to send scanned emails             │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Phase 2: Runtime Operation (Message Flow)

```
TIME: 14:32:15.000

[1] USER COMPOSES EMAIL
════════════════════════════════════════════════════════════════
Alice (alice@company.com) composes:
  TO: bob@gmail.com
  SUBJECT: Q2 Report
  BODY: [Document with financial data]

She clicks SEND in Outlook.

─────────────────────────────────────────────────────────────────

[2] MAIL SERVER RECEIVES
════════════════════════════════════════════════════════════════
Exchange server (your on-premises server) receives the message.

Exchange Router Logic:
  "Is bob@gmail.com internal? NO"
  "Should this route through CEGP? YES"
  → CEGP endpoint: relay.mx.trendmicro.com

Sends message to CEGP cloud.

TIME: 14:32:15.250 (250ms elapsed)

─────────────────────────────────────────────────────────────────

[3] CEGP SCANS MESSAGE
════════════════════════════════════════════════════════════════
relay.mx.trendmicro.com (CEGP endpoint) receives message.

CEGP Processing:
  ├─ Virus/malware scan: CLEAN ✓
  ├─ Phishing detection: No suspicious links ✓
  ├─ BEC analysis: From known user ✓
  ├─ DLP rules: Contains financial data
  │  └─ Policy: "Add disclaimer to financial emails"
  │  └─ Action: APPROVED (user authorized to send)
  └─ Attachment handling: Clean PDF ✓

Headers Modified:
  X-TrendMicro-Scanned: Yes
  X-TrendMicro-Status: Clean
  X-TrendMicro-Action: Approved
  X-TrendMicro-Scan-Time: 1250ms

CEGP Domain Lookup:
  "Where is company.com's outbound server?"
  → Check CEGP console configuration
  → Found: User-defined mail servers
  → Server IP/FQDN: relay.email-security.svc.cluster.local:25

TIME: 14:32:16.250 (1.25 seconds elapsed)

─────────────────────────────────────────────────────────────────

[4] RELAY CONTAINER RECEIVES
════════════════════════════════════════════════════════════════
Scanned message arrives at relay container port 25.

Relay Policy Daemon Validation:

  Check #1: Is sender IP allowed?
    Source IP: 150.70.149.5 (CEGP endpoint)
    permit-ips.conf: Contains 150.70.149.0/27 ✓ PASS

  Check #2: Is sender domain whitelisted?
    MAIL FROM: <alice@company.com>
    domain = "company.com"
    domains.conf: Contains "company.com" ✓ PASS

  Check #3: Is sender within rate limits?
    Current: 234 msgs/min from 150.70.149.5
    Limit: 2,000 msgs/min per IP ✓ PASS (within 2000/min)

  Check #4: Is recipient within rate limits?
    Current: 45 msgs/min to bob@gmail.com
    Limit: 200 msgs/min per recipient ✓ PASS

  Check #5: Message size acceptable?
    Size: 245 KB
    Limit: 50 MB ✓ PASS

  Check #6: Recipient count acceptable?
    Count: 1
    Limit: 99,999 ✓ PASS

All Validations Passed!

Postfix Queue:
  Message stored in: /var/spool/postfix/defer/
  Message ID: <alice-company-1234@relay.local>
  Status: Queued for delivery

CEGP Response: SMTP 250 OK "Message accepted, queued for delivery"

TIME: 14:32:16.500 (1.5 seconds elapsed)
Metrics Logged:
  relay_messages_received_total{domain="company.com",src_ip="150.70.149.5"} = 1
  relay_queue_size_messages = 47

─────────────────────────────────────────────────────────────────

[5] RELAY DELIVERS TO DESTINATION
════════════════════════════════════════════════════════════════
Postfix Queue Manager processes the queued message.

Step 1: Determine Destination
  RCPT TO: <bob@gmail.com>
  Destination domain: "gmail.com"

Step 2: DNS MX Lookup
  Query: What is the mail server for gmail.com?
  Result: gmail.com has several MX records:
    Priority 5: gmail-smtp-in.l.google.com (142.251.41.5)
    Priority 10: alt1.gmail-smtp-in.l.google.com (142.251.40.5)
    Priority 20: alt2.gmail-smtp-in.l.google.com (142.251.41.6)
    ...and more

Step 3: Connect to First MX Server
  Server: gmail-smtp-in.l.google.com:25
  Connection: TCP port 25 established
  Time: 14:32:17.000

Step 4: SMTP Transaction
  → EHLO relay.email-security.svc.cluster.local
  ← 250 PONG (Gmail accepts the greeting)
  
  → MAIL FROM: <alice@company.com>
  ← 250 OK (sender accepted)
  
  → RCPT TO: <bob@gmail.com>
  ← 250 OK (recipient accepted)
  
  → DATA
  ← 354 Start mail input
  → [Full message headers and body]
  → [CEGP scan headers included]
  → . (end of data marker)
  ← 250 OK Message accepted for delivery (ID: Gmail-internal-ID)

Step 5: Connection Close
  → QUIT
  ← 221 Bye

Postfix Actions:
  ✓ Remove message from queue
  ✓ Mark as delivered
  ✓ Update delivery statistics

TIME: 14:32:18.500 (3.5 seconds elapsed)
Metrics Logged:
  relay_messages_delivered_total{status="success"} = 1
  relay_delivery_latency_seconds = 3.5
  relay_queue_size_messages = 46

─────────────────────────────────────────────────────────────────

[6] FINAL DELIVERY
════════════════════════════════════════════════════════════════
Gmail processes the message.

Gmail's Incoming Mail Server:
  ✓ Receives the message
  ✓ Checks headers (X-TrendMicro-Scanned: Yes)
  ✓ Applies additional Gmail spam filters
  ✓ Stores in bob@gmail.com inbox

Bob sees the email in his inbox:
  FROM: alice@company.com
  SUBJECT: Q2 Report
  RECEIVED: 14:32:18 (3.5 seconds after Alice sent it)
  STATUS: Safe (scanned by CEGP)

─────────────────────────────────────────────────────────────────

[7] LOGGING & MONITORING
════════════════════════════════════════════════════════════════
Relay Container Structured Logs:

{
  "timestamp": "2025-03-25T14:32:18.500Z",
  "event": "message_delivered",
  "src_ip": "150.70.149.5",
  "sender_domain": "company.com",
  "from": "alice@company.com",
  "rcpt": "bob@gmail.com",
  "message_id": "<alice-company-1234@relay.local>",
  "size_bytes": 245000,
  "rate_limit_check": "passed",
  "destination_mta": "gmail-smtp-in.l.google.com",
  "delivery_status": "success",
  "cegp_processing_time_ms": 1250,
  "relay_processing_time_ms": 3500,
  "total_time_ms": 3750
}

Prometheus Metrics Updated:
  relay_messages_delivered_total{status="success"} += 1
  relay_delivery_latency_seconds.observe(3.5)
  relay_recipient_count.observe(1)
  relay_message_size_bytes.observe(245000)
```

### Phase 3: Scaling Under Load

```
NORMAL LOAD (Daytime)
═════════════════════════════════════════════════════════════

Pod Count: 3 (always running)
CPU per Pod: 35% average
Memory per Pod: 620 MB

Throughput:
  670 msg/min per pod × 3 pods = 2,000 msg/min total capacity
  Current: 500 msg/min ✓ Healthy

HPA Status: IDLE (not scaling)

─────────────────────────────────────────────────────────────────

TRAFFIC SPIKE (Viral Campaign / Large Mailing)
═════════════════════════════════════════════════════════════

Time: 15:00:00
Sudden increase: 1,200 msg/min → CEGP starts sending heavily

Relay Pod Metrics:
  CPU: 35% → 50% → 65% → 72% ← TRIGGERS SCALE-UP (70% threshold)
  Memory: 620 MB → 750 MB → 780 MB ← TRIGGERS SCALE-UP (75% threshold)

HPA Detects High Load:
  "Average CPU across pods: 72%"
  "Average Memory across pods: 78%"
  "Metric above threshold"

Scale-Up Action (Immediate):
  Time: 15:00:30 (30 seconds after spike detected)
  Action: Create new pods
  Target: 6 pods (100% increase, doubled capacity)

New Pods Starting:
  ├─ Pod 4 (Pending → Running): 15:00:35
  ├─ Pod 5 (Pending → Running): 15:00:35
  └─ Pod 6 (Pending → Running): 15:00:40

Capacity Impact:
  Before: 3 pods × 670 msg/min = 2,000 msg/min max
  After: 6 pods × 670 msg/min = 4,000 msg/min max
  Current load: 1,200 msg/min ✓ Healthy again

CPU per Pod drops to 40%

HPA Status: SCALING (3 → 6 pods)

─────────────────────────────────────────────────────────────────

FURTHER ESCALATION (Extreme Spike)
═════════════════════════════════════════════════════════════

Time: 15:01:00
Message rate continues to climb: 2,500 msg/min

HPA Detects: Still high CPU (68%)

Scale-Up Action #2:
  Target: 12 pods (200% of original, +9 pods)
  
  New Pods Starting:
    ├─ Pod 7 (15:00:45)
    ├─ Pod 8 (15:00:45)
    ├─ Pod 9 (15:01:00)
    ├─ Pod 10 (15:01:00)
    ├─ Pod 11 (15:01:15)
    └─ Pod 12 (15:01:15)

New Capacity:
  12 pods × 670 msg/min = 8,040 msg/min max
  Current load: 2,500 msg/min ✓ Healthy
  CPU per Pod: 35%

Maximum Capacity Reached:
  If load exceeds 20 pods × 670 msg/min = 13,400 msg/min
  Rate limiting activates (4xx response to CEGP)
  CEGP retries automatically

HPA Status: SCALED to 12 pods

─────────────────────────────────────────────────────────────────

SCALE-DOWN (Back to Normal)
═════════════════════════════════════════════════════════════

Time: 16:00:00 (1 hour after spike)
Message rate drops: 2,500 msg/min → 300 msg/min

HPA Detects Low Load:
  "Average CPU < 70% for 5 minutes"
  "Average Memory < 75% for 5 minutes"

Scale-Down Action (Conservative):
  Stabilization window: 300 seconds (5 minutes)
  Reduction: 50% of excess capacity
  Current: 12 pods → Target: 8 pods

Scale-Down Behavior:
  Pods terminated gracefully (SIGTERM)
  In-flight messages completed
  New messages routed to remaining pods
  
Termination Order:
  ├─ Pod 12 (15:05:00) - TERMINATING
  ├─ Pod 11 (15:05:30) - TERMINATING
  ├─ Pod 10 (15:05:45) - TERMINATING
  ├─ Pod 9 (15:06:00) - TERMINATING
  └─ Pods 1-8 continue running

New Status: 8 pods
CPU per Pod: 28%
HPA Status: SCALING DOWN

─────────────────────────────────────────────────────────────────

RETURN TO BASELINE (Night Hours / Low Activity)
═════════════════════════════════════════════════════════════

Time: 22:00:00 (Late evening, low activity)
Message rate: 150 msg/min

HPA Detects Sustained Low Load:
  "Average CPU < 70% for 10 minutes"

Scale-Down Action (Final):
  Current: 8 pods → Target: 3 pods (minimum)

Graceful Termination:
  ├─ Pod 8 (22:05:00) - TERMINATING
  ├─ Pod 7 (22:05:30) - TERMINATING
  ├─ Pod 6 (22:05:45) - TERMINATING
  ├─ Pod 5 (22:06:00) - TERMINATING
  └─ Pods 1-3 continue running (minimum replicas)

Final Status: 3 pods
CPU per Pod: 12% (idle)
Memory per Pod: 380 MB

HPA Status: IDLE (scaled to minimum)

Ready for next spike.
```

---

## Architecture Overview

### System Components

```
┌────────────────────────────────────────────────────────────────┐
│                    RELAY CONTAINER INTERNALS                   │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 1. SMTP Server (Postfix)                                │   │
│  │    - Listens on port 25 (SMTP)                          │   │
│  │    - Receives messages from CEGP                        │   │
│  │    - Implements RFC 5321 (SMTP protocol)                │   │
│  │    - Maintains local queue in /var/spool/postfix/       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                          ▲                                      │
│                          │                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 2. Policy Daemon (Python/asyncio)                       │   │
│  │    - Validates CEGP source IP (permit-ips.conf)        │   │
│  │    - Validates sender domain (domains.conf)            │   │
│  │    - Enforces rate limits (Redis token bucket)         │   │
│  │    - Checks message size & recipient count             │   │
│  │    - Returns ACCEPT/DEFER/REJECT to Postfix            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                          ▲                                      │
│                          │                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 3. Redis Cache                                          │   │
│  │    - Stores rate limit counters                         │   │
│  │    - Session state across pods                          │   │
│  │    - Fast in-memory lookups                             │   │
│  │    - TTL-based expiration                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                          ▲                                      │
│                          │                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 4. Health Check & Metrics (HTTP :9090)                 │   │
│  │    - /health → Kubernetes liveness/readiness           │   │
│  │    - /metrics → Prometheus scrape endpoint             │   │
│  │    - JSON structured logging to stdout                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

---

## Key Features & Benefits

### Feature Matrix

```
┌────────────────────────────────────────────────────────────┐
│ FEATURE                    │ STATUS   │ NOTES                │
├────────────────────────────────────────────────────────────┤
│ Rate Limiting              │ ✓ FULL   │ 2000/min IP, 200/min │
│                            │          │ recipient             │
├────────────────────────────────────────────────────────────┤
│ Auto-Scaling (HPA)         │ ✓ FULL   │ 3-20 pods, CPU/mem  │
├────────────────────────────────────────────────────────────┤
│ Message Queuing            │ ✓ FULL   │ Local disk queue    │
├────────────────────────────────────────────────────────────┤
│ Domain Whitelist           │ ✓ FULL   │ Hot-reload via      │
│                            │          │ ConfigMap           │
├────────────────────────────────────────────────────────────┤
│ IP ACL (CEGP)              │ ✓ FULL   │ Permit/Deny lists   │
├────────────────────────────────────────────────────────────┤
│ Retry Logic                │ ✓ FULL   │ RFC 5321 compliant  │
├────────────────────────────────────────────────────────────┤
│ Prometheus Metrics         │ ✓ FULL   │ 15+ metrics         │
├────────────────────────────────────────────────────────────┤
│ Structured Logging         │ ✓ FULL   │ JSON format         │
├────────────────────────────────────────────────────────────┤
│ TLS/STARTTLS               │ ✓ FULL   │ Configurable        │
├────────────────────────────────────────────────────────────┤
│ DNS MX Lookup              │ ✓ FULL   │ Automatic routing   │
├────────────────────────────────────────────────────────────┤
│ Load Balancing             │ ✓ FULL   │ Service LB + SMTP LB│
├────────────────────────────────────────────────────────────┤
│ Pod Anti-Affinity          │ ✓ FULL   │ Spread across nodes │
├────────────────────────────────────────────────────────────┤
│ PodDisruptionBudget        │ ✓ FULL   │ Min 2 pods always   │
├────────────────────────────────────────────────────────────┤
│ Multi-Region Support       │ ✓ PLANNED│ Regional endpoints  │
├────────────────────────────────────────────────────────────┤
│ GDPR Compliance            │ ✓ FULL   │ Audit logging       │
└────────────────────────────────────────────────────────────┘
```

### Benefits Over Direct CEGP → Destination

| Aspect | Without Relay | With Relay Container |
|--------|---------------|----------------------|
| **Message Queue** | In CEGP cloud only | Local + cloud (redundancy) |
| **Rate Limiting** | CEGP-only | Local enforcement (faster feedback) |
| **Auto-Scaling** | Manual CEGP resize | Automatic K8s HPA |
| **On-Prem Integration** | Difficult | Native Kubernetes |
| **Cost** | Higher (CEGP resources) | Lower (distributed load) |
| **Visibility** | CEGP console only | Prometheus + logs + console |
| **Email Continuity** | Limited | Full (if CEGP down) |
| **Compliance** | CEGP audit trail | Complete local audit trail |
| **Failover** | CEGP handles | Local + CEGP both handle |
| **Customization** | Limited | Full (your infrastructure) |

---

## Deployment Models

### Model 1: Single Kubernetes Cluster (Recommended)

```
┌─────────────────────────────────────────────────────┐
│ Single Kubernetes Cluster (e.g., on-premises)       │
│                                                     │
│ ┌──────────────────────────────────────────────┐   │
│ │ email-security namespace                     │   │
│ │                                              │   │
│ │ ┌────────────────────────────────────────┐   │   │
│ │ │ Service: cegp-smtp-relay               │   │   │
│ │ │ Type: LoadBalancer                     │   │   │
│ │ │ Port: 25 (external)                    │   │   │
│ │ │                                        │   │   │
│ │ │ ┌─────────────────────────────────┐   │   │   │
│ │ │ │ Pod 1: Relay Container          │   │   │   │
│ │ │ │ CPU: 500m, Memory: 512Mi        │   │   │   │
│ │ │ │ Status: Running                 │   │   │   │
│ │ │ └─────────────────────────────────┘   │   │   │
│ │ │                                        │   │   │
│ │ │ ┌─────────────────────────────────┐   │   │   │
│ │ │ │ Pod 2: Relay Container          │   │   │   │
│ │ │ │ CPU: 500m, Memory: 512Mi        │   │   │   │
│ │ │ │ Status: Running                 │   │   │   │
│ │ │ └─────────────────────────────────┘   │   │   │
│ │ │                                        │   │   │
│ │ │ ┌─────────────────────────────────┐   │   │   │
│ │ │ │ Pod 3: Relay Container          │   │   │   │
│ │ │ │ CPU: 500m, Memory: 512Mi        │   │   │   │
│ │ │ │ Status: Running                 │   │   │   │
│ │ │ └─────────────────────────────────┘   │   │   │
│ │ │                                        │   │   │
│ │ │ HPA: min=3, max=20                    │   │   │
│ │ │ ConfigMaps: relay-policy, postfix-cfg │   │   │
│ │ │ Secrets: relay-tls-certs              │   │   │
│ │ └────────────────────────────────────────┘   │   │
│ └──────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘

Characteristics:
✓ Simple to deploy and maintain
✓ Single point of management
✓ Lower latency (local network)
✓ Best for: Most customers

Costs:
- Kubernetes cluster: $300-500/month
- Relay container: ~$50/month (minimal resources)
- Total: Lower than managed CEGP scaling
```

### Model 2: Multi-Region Deployment

```
┌─────────────────────────────────────────────────────────────┐
│ Multi-Region Setup (High Availability)                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ REGION 1: US-EAST                                           │
│ ┌──────────────────────────────────────────────────────┐    │
│ │ Kubernetes Cluster A                                 │    │
│ │                                                      │    │
│ │ Service: cegp-smtp-relay                            │    │
│ │ Load Balancer IP: 203.0.113.10 (US-East)           │    │
│ │                                                      │    │
│ │ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │    │
│ │ │ Pod 1       │ │ Pod 2       │ │ Pod 3       │    │    │
│ │ └─────────────┘ └─────────────┘ └─────────────┘    │    │
│ │                                                      │    │
│ │ HPA: 3-20 pods                                       │    │
│ └──────────────────────────────────────────────────────┘    │
│                          ▲                                  │
│                    Failover Route                           │
│                    (If down, use Region 2)                  │
│                          │                                  │
│ REGION 2: US-WEST                                          │
│ ┌──────────────────────────────────────────────────────┐    │
│ │ Kubernetes Cluster B                                 │    │
│ │                                                      │    │
│ │ Service: cegp-smtp-relay                            │    │
│ │ Load Balancer IP: 198.51.100.20 (US-West)          │    │
│ │                                                      │    │
│ │ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │    │
│ │ │ Pod 1       │ │ Pod 2       │ │ Pod 3       │    │    │
│ │ └─────────────┘ └─────────────┘ └─────────────┘    │    │
│ │                                                      │    │
│ │ HPA: 3-20 pods                                       │    │
│ └──────────────────────────────────────────────────────┘    │
│                                                              │
│ DNS Configuration (GeoDNS or Round-Robin):                  │
│ relay.company.local → 203.0.113.10 (primary, US-East)     │
│ relay.company.local → 198.51.100.20 (secondary, US-West)  │
│                                                              │
│ Load Distribution:                                          │
│ - CEGP sends 70% to US-East, 30% to US-West              │
│ - If US-East unavailable, 100% to US-West               │
│                                                              │
└─────────────────────────────────────────────────────────────┘

Characteristics:
✓ Maximum availability
✓ Geographic redundancy
✓ Better latency for global users
✓ Automatic failover

Costs:
- 2x Kubernetes clusters
- 2x Relay containers
- Total: ~$700-1000/month
- Best for: Enterprise customers, SLAs > 99.9%
```

### Model 3: Hybrid (Cloud + On-Premises)

```
┌─────────────────────────────────────────────────────────┐
│ Hybrid Deployment                                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ ┌──────────────────────┐                               │
│ │ AWS EKS (Cloud)      │                               │
│ │                      │                               │
│ │ cegp-smtp-relay      │ ←── Primary (99% traffic)    │
│ │ 3-20 pods            │                              │
│ │ Auto-scaling         │                              │
│ │ Managed service      │                              │
│ └──────────────────────┘                               │
│          ▲ │                                            │
│          │ │                                            │
│  Failover│ │ Primary                                    │
│          │ │                                            │
│          │ ▼                                            │
│ ┌──────────────────────────────┐                       │
│ │ On-Premises Kubernetes        │                      │
│ │                               │                      │
│ │ cegp-smtp-relay-backup        │ ←── Failover        │
│ │ 1-3 pods (minimal)            │     (1% traffic)     │
│ │ Manual scaling                │                      │
│ │ Existing infrastructure       │                      │
│ └──────────────────────────────┘                       │
│                                                         │
└─────────────────────────────────────────────────────────┘

Characteristics:
✓ Leverages existing on-premises infra
✓ Cloud handles main load
✓ On-premises as backup
✓ Lower cloud costs

Costs:
- Cloud K8s (AWS EKS): ~$400/month
- On-premises: Included in existing
- Total: Moderate
```

---

## Message Lifecycle

### Complete Journey of One Email

```
ALICE's Perspective:
══════════════════════════════════════════════════════════════

[14:32:00] Alice composes email in Outlook
           TO: bob@gmail.com
           [Clicks SEND]

[14:32:02] "Your message has been sent" ✓


EXCHANGE SERVER'S Perspective:
══════════════════════════════════════════════════════════════

[14:32:00.5] Message arrives at Exchange SMTP
[14:32:01] Router: "Is bob@gmail.com internal?" → NO
[14:32:01] Router: "Route via CEGP?" → YES
[14:32:01] Forwards to relay.mx.trendmicro.com


CEGP CLOUD'S Perspective:
══════════════════════════════════════════════════════════════

[14:32:01.5] Message arrives at CEGP inbound
[14:32:02] Threat scanning:
            - Malware: CLEAN
            - Phishing: CLEAN
            - BEC: LEGITIMATE USER
            - DLP: APPROVED
[14:32:02.5] Apply policies:
             - Add headers
             - Clean attachments
[14:32:02.5] Outbound routing:
             - Domain: company.com
             - Type: User-defined servers
             - Server: relay container:25
[14:32:02.6] Forward to relay


RELAY CONTAINER'S Perspective:
══════════════════════════════════════════════════════════════

[14:32:02.7] SMTP connection from 150.70.149.5 (CEGP)
[14:32:02.8] Validate:
             - IP in permit list: ✓
             - Domain in whitelist: ✓
             - Rate limits: ✓
             - Message size: ✓
[14:32:02.9] Queue message: /var/spool/postfix/defer/
[14:32:03] Return: SMTP 250 OK
[14:32:03.1] Process delivery:
             - DNS MX lookup for gmail.com
             - Connect to gmail server
[14:32:04] Send message to Gmail
[14:32:04.5] Receive: 250 OK (Gmail accepts)
[14:32:04.6] Mark delivered
[14:32:04.7] Log metrics


BOB's Perspective:
══════════════════════════════════════════════════════════════

[14:32:05] Email arrives in Gmail inbox
           FROM: alice@company.com
           SUBJECT: Q2 Report
           [Scanned by CEGP - SAFE] ✓

Total time: 5 seconds
Path: Alice → Exchange → CEGP → Relay → Gmail → Bob
```

---

## Monitoring & Management

### What You Can Monitor

```
PROMETHEUS METRICS (Real-Time)
═══════════════════════════════════════════════════════════════

Current Queue Size:
  relay_queue_size_messages = 42 messages waiting

Message Rates:
  relay_messages_received_total = 15,234 (cumulative)
  rate(relay_messages_received_total[5m]) = 267 msg/min (5-min avg)

Delivery Status:
  relay_messages_delivered_total = 15,156 (successful)
  relay_messages_bounced_total = 45 (permanent failures)
  relay_messages_deferred_total = 33 (temporary failures)

Rate Limiting:
  relay_rate_limit_hits_total = 0 (no hits in last hour) ✓

Pod Status:
  relay_container_cpu_usage = 450m / 500m (90%) ← High!
  relay_container_memory_usage = 600Mi / 1Gi (60%) ✓
  relay_running_pods = 3

Delivery Latency:
  relay_delivery_latency_seconds (histogram):
    p50: 2.5 seconds
    p95: 4.2 seconds
    p99: 6.8 seconds

CEGP Connection Status:
  relay_cegp_connections_total = 892 (total connections)
  rate(relay_cegp_connections[5m]) = 15 conn/min
```

### Dashboard Query Examples

```sql
-- Top senders by message count (last hour)
SELECT sender_domain, COUNT(*) as msg_count
FROM relay_messages
WHERE timestamp > now() - interval '1 hour'
GROUP BY sender_domain
ORDER BY msg_count DESC
LIMIT 10;

-- Messages per minute over time (5m intervals)
SELECT timestamp, COUNT(*) as msg_count
FROM relay_messages
GROUP BY time_bucket('5 minutes', timestamp)
ORDER BY timestamp DESC;

-- Rate limit violations in last 24 hours
SELECT time, src_ip, violation_type, COUNT(*) as hits
FROM relay_rate_limit_violations
WHERE timestamp > now() - interval '24 hours'
GROUP BY time_bucket('1 hour', timestamp), src_ip, violation_type;

-- Delivery latency percentiles
SELECT
  percentile_cont(0.50) WITHIN GROUP (ORDER BY delivery_latency_ms) as p50,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY delivery_latency_ms) as p95,
  percentile_cont(0.99) WITHIN GROUP (ORDER BY delivery_latency_ms) as p99
FROM relay_messages
WHERE timestamp > now() - interval '1 hour';
```

---

## Load Balancing

### Load Balancing Methods Available

```
METHOD 1: Kubernetes Service Load Balancing (BUILT-IN)
═════════════════════════════════════════════════════════════

Type: ClusterIP (internal) or LoadBalancer (external)

Mechanism:
  CEGP sends to single IP: relay.email-security.svc.cluster.local
  Kubernetes automatically distributes traffic across 3-20 pods
  Load balancing algorithm: Round-robin (kernel-level)

Configuration:
  apiVersion: v1
  kind: Service
  metadata:
    name: cegp-smtp-relay
    namespace: email-security
  spec:
    type: LoadBalancer              # External access
    selector:
      app: cegp-smtp-relay
    ports:
      - port: 25
        targetPort: 25
        protocol: TCP
    sessionAffinity: None            # No sticky sessions

How It Works:
  CEGP connects to: <EXTERNAL-IP>:25
  
  Kubernetes iptables rules:
    <EXTERNAL-IP>:25 → Pod-1:25 (33% of connections)
    <EXTERNAL-IP>:25 → Pod-2:25 (33% of connections)
    <EXTERNAL-IP>:25 → Pod-3:25 (33% of connections)
  
  As pods scale to 10:
    <EXTERNAL-IP>:25 → Pod-1 through Pod-10 (10% each)

Metrics:
  Load per pod: Messages per minute / Number of pods
  3 pods: 667 msg/min per pod
  10 pods: 200 msg/min per pod
  20 pods: 100 msg/min per pod


METHOD 2: SMTP Load Balancing (Connection Pooling)
═════════════════════════════════════════════════════════════

Mechanism:
  CEGP opens persistent SMTP connection
  Keeps connection open for multiple messages
  Connection reused for 10-100+ messages

Implementation:
  - Kubernetes Service handles connection level load balancing
  - Once established, CEGP sends all messages on same connection
  - If connection drops, CEGP opens new one (to different pod)

Benefits:
  ✓ Lower latency (connection reuse)
  ✓ Efficient (fewer TCP handshakes)
  ✓ Natural load distribution

Example:
  Connection A (CEGP) → Pod 1
    [Message 1-50 on conn A]
  
  Connection B (CEGP) → Pod 2
    [Message 51-100 on conn B]
  
  Connection C (CEGP) → Pod 3
    [Message 101-150 on conn C]

Balance: ~50 messages per pod per connection


METHOD 3: Sticky Session Load Balancing (Optional)
═════════════════════════════════════════════════════════════

When: If you need message ordering per sender

Configuration:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 3600

How It Works:
  All traffic from CEGP IP → Same pod
  Ensures FIFO message ordering
  Helps with debugging (logs on one pod)

Trade-offs:
  Pro: ✓ Message ordering guaranteed
  Con: ✗ Uneven load distribution
       ✗ One pod may be busier

When to Use:
  - Only if ordering is critical
  - Most customers don't need this


METHOD 4: DNS Round-Robin (Multi-Region)
═════════════════════════════════════════════════════════════

For Geographic Distribution:

Configuration (CloudFlare / Route53):
  relay.company.local:
    → 203.0.113.10 (US-East K8s LB)
    → 198.51.100.20 (US-West K8s LB)
    → 192.0.2.30 (EU K8s LB)

How CEGP Sees It:
  1. First connection attempt:
     DNS lookup: relay.company.local → 203.0.113.10
     CEGP connects to US-East, sends messages
  
  2. If US-East fails:
     DNS lookup (with TTL): relay.company.local → 198.51.100.20
     CEGP connects to US-West, sends messages
  
  3. If both fail:
     DNS lookup: relay.company.local → 192.0.2.30
     CEGP connects to EU, sends messages

Load Distribution (with GeoDNS):
  - US clients → US-East (lowest latency)
  - EU clients → EU (lowest latency)
  - Fallback to next region if primary down


METHOD 5: HAProxy (Optional, Advanced)
═════════════════════════════════════════════════════════════

For Complex Load Balancing Needs:

Scenario: Want more control than Kubernetes Service provides

Configuration:
  global
    maxconn 100000
  
  frontend smtp_in
    bind 0.0.0.0:25
    default_backend relay_servers
  
  backend relay_servers
    balance roundrobin
    option forwardfor
    option httpchk GET /health
    
    server relay1 10.0.1.10:25 check
    server relay2 10.0.1.11:25 check
    server relay3 10.0.1.12:25 check
    server relay4 10.0.1.13:25 check
    
    # Add servers dynamically
    # Weighted load balancing
    # Connection limits per backend

Metrics:
  - Connections per backend
  - Errors per backend
  - Response times
  - Automatic drain on backend failure

When to Use HAProxy:
  ✓ Very high load (100k+ msg/min)
  ✓ Need granular control
  ✓ Custom algorithm (weighted, least-conn)
  ✓ Session limits per backend

Deployment:
  HAProxy Pod (singleton or HA pair) →
  Kubernetes Service → Relay Pods


RECOMMENDED: Kubernetes Service (Default)
═════════════════════════════════════════════════════════════

Why:
  ✓ Native Kubernetes integration
  ✓ Automatic scaling (no config changes)
  ✓ Highly efficient (kernel-level)
  ✓ No additional components
  ✓ Built-in health checks
  ✓ Works with any cloud provider

Configuration (Already Included):
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
      - port: 25
        targetPort: 25
        protocol: TCP
  ```

This handles everything automatically!
```

### Load Distribution Example

```
SCENARIO: 3 Pods, Steady-State Load of 2,000 msg/min

┌─────────────────────────────────────────────────────┐
│ Load Distribution Across Pods                       │
├─────────────────────────────────────────────────────┤
│                                                     │
│ Total Incoming: 2,000 msg/min from CEGP            │
│                                                     │
│         Pod 1              Pod 2              Pod 3 │
│       ┌────────────┐    ┌────────────┐    ┌──────────┐│
│       │ 667 msg/min│    │ 667 msg/min│    │ 667 msg/min
│       │ CPU: 32%   │    │ CPU: 32%   │    │ CPU: 32%  │
│       │ Memory: 600M│   │ Memory: 600M│   │ Memory: 600M
│       │ Connections│    │ Connections│    │ Connections
│       │ to Gmail   │    │ to Yahoo   │    │ to Outlook│
│       └────────────┘    └────────────┘    └──────────┘│
│            │                   │                │     │
│            └───────────────────┼───────────────┘     │
│                                │                      │
│                    Kubernetes Service:25              │
│                  relay.company.local:25               │
│                   (203.0.113.100:25)                 │
│                                                      │
└────────────────────────────────────────────────────┘


SCENARIO: Traffic Spike to 4,000 msg/min

Kubernetes HPA Detects High Load:
  Time 0s:      3 pods, 2000 msg/min (baseline)
  Time 30s:     6 pods detected, scaling to 6
  Time 60s:     6 pods online

┌──────────────────────────────────────────────────────┐
│ Load Distribution After Scale-Up to 6 Pods           │
├──────────────────────────────────────────────────────┤
│                                                      │
│ Pod 1  Pod 2  Pod 3  Pod 4  Pod 5  Pod 6            │
│ ────   ────   ────   ────   ────   ────             │
│ 667    667    667    667    667    667              │
│ msg/m  msg/m  msg/m  msg/m  msg/m  msg/m            │
│ 24%    24%    24%    24%    24%    24% CPU           │
│                                                      │
│ Total: 4,000 msg/min ✓ Balanced                     │
│ CPU per pod: 24% (healthy, with headroom)           │
│                                                      │
└──────────────────────────────────────────────────────┘


SCENARIO: One Pod Fails

Before Pod Failure:
  6 pods × 667 msg/min = 4,000 msg/min total
  No issues

Pod 5 Crashes:
  Kubernetes detects pod is not running
  Service automatically removes Pod 5 from load balancer
  
  Remaining: 5 pods

Immediate Effect:
  4,000 msg/min / 5 pods = 800 msg/min per pod
  CPU: 32% → 38% per pod (still healthy)
  
  Messages queued during transition: ~10-20

Recovery:
  HPA detects: CPU 38%, Memory 70%
  Threshold: CPU < 70%, so no automatic scale-up
  
  Manual action (or wait):
  kubectl scale deployment cegp-smtp-relay --replicas=6
  
  New Pod 6 starts (15-30 seconds)
  Back to: 6 pods, 667 msg/min each, 24% CPU

Fault Tolerance:
  ✓ PodDisruptionBudget ensures minimum 2 pods always available
  ✓ No messages lost (queued locally)
  ✓ Automatic recovery to original pod count
```

---

## Troubleshooting

### Quick Troubleshooting Guide

```
ISSUE: "Connection refused" from CEGP
═════════════════════════════════════════════════════════════

Check 1: Pod Status
  kubectl get pods -n email-security
  → All pods Running? If not, check logs

Check 2: Service Status
  kubectl get svc -n email-security cegp-smtp-relay
  → Has EXTERNAL-IP assigned? If not:
    kubectl describe svc cegp-smtp-relay -n email-security

Check 3: Network Policy
  kubectl get networkpolicies -n email-security
  → Any policies blocking CEGP IPs?

Check 4: Firewall Rules
  → Is port 25 open from CEGP to relay service?
  → Check cloud provider security groups


ISSUE: "452 Service temporarily unavailable"
═════════════════════════════════════════════════════════════

Cause: Rate limit exceeded or queue backed up

Check 1: Pod Capacity
  kubectl get deployment cegp-smtp-relay -n email-security
  → Replicas: 3? 5? 10?
  → If stuck at 3, HPA might not be scaling

Check 2: Current Load
  kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- \
    postqueue -p | wc -l
  → Number of queued messages?

Check 3: Pod Resources
  kubectl top pods -n email-security
  → CPU and memory usage?
  → If CPU > 80%, need to scale

Check 4: Rate Limit Metrics
  curl http://<relay-ip>:9090/metrics | grep rate_limit
  → Any rate limit hits? If yes:
    - Too many messages in short time
    - Need to scale up (add more pods)
    - Or: CEGP is sending in bursts


ISSUE: Messages Not Arriving at Destination
═════════════════════════════════════════════════════════════

Check 1: Message in Queue?
  kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- \
    postqueue -p
  → Messages stuck? If yes:
    - Destination DNS not resolving
    - Destination SMTP server unreachable
    - Message rejected by destination

Check 2: Logs
  kubectl logs cegp-smtp-relay-<pod> -n email-security | \
    grep "bob@gmail.com"
  → What does the log say?
  → Delivery success? Error details?

Check 3: DNS Resolution
  kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- \
    nslookup gmail.com
  → Can pod resolve destination domains?

Check 4: Connectivity to Destination
  kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- \
    nc -zv gmail.com 25
  → Can pod connect to destination on port 25?


ISSUE: High CPU Usage (Pods Keep Crashing)
═════════════════════════════════════════════════════════════

Check 1: Message Volume
  → Is CEGP sending more than 2000 msg/min?
  → Expected: 667 msg/min per pod (3 pods = 2000 msg/min)

Check 2: Scaling
  kubectl get hpa cegp-smtp-relay-hpa -n email-security
  → Current replicas?
  → If stuck at 3, check HPA events:
    kubectl describe hpa cegp-smtp-relay-hpa -n email-security

Check 3: CPU Limit
  kubectl get deployment cegp-smtp-relay -n email-security -o yaml | \
    grep -A 5 "limits:"
  → CPU limit: 2000m
  → If constantly hitting limit, need to scale or increase limit

Solution:
  Option 1: Scale up
    kubectl scale deployment cegp-smtp-relay --replicas=10 \
      -n email-security
  
  Option 2: Increase limits
    kubectl set resources deployment cegp-smtp-relay \
      --limits cpu=4000m,memory=2Gi \
      -n email-security
  
  Option 3: Reduce message rate
    Contact CEGP support to optimize scanning


ISSUE: "Domain not in relay list" Errors
═════════════════════════════════════════════════════════════

Check 1: Current Domain Configuration
  kubectl get configmap relay-policy -n email-security -o yaml
  → domains.conf field contains?

Check 2: Add Missing Domain
  kubectl patch configmap relay-policy -n email-security \
    --type merge -p '{"data":{"domains.conf":"company.com\nnew-domain.org"}}'

Check 3: Verify Changes
  kubectl get configmap relay-policy -n email-security \
    -o jsonpath='{.data.domains\.conf}'


ISSUE: Only Some Pods Are Handling Traffic
═════════════════════════════════════════════════════════════

Check 1: Pod Health
  kubectl get pods -n email-security
  → All pods "Running" and "Ready"?
  → If any "NotReady", check:
    kubectl describe pod <pod-name> -n email-security

Check 2: Service Endpoint Discovery
  kubectl get endpoints -n email-security cegp-smtp-relay
  → Should list all pod IPs
  → If missing pods, not healthy

Check 3: Service Selector
  kubectl get svc cegp-smtp-relay -n email-security -o yaml | \
    grep -A 5 "selector:"
  → Selector matches pod labels?

Fix:
  kubectl rollout restart deployment/cegp-smtp-relay \
    -n email-security
  → Forces all pods to restart
  → Re-registers with service
```

---

## Conclusion

The **CEGP SMTP Relay Container** is a production-ready solution that:

✓ Handles email volume from CEGP to your infrastructure  
✓ Auto-scales from 3-20 pods automatically  
✓ Never loses messages (local queue + retry logic)  
✓ Enforces rate limits per Trend Micro specs  
✓ Provides complete visibility (Prometheus + logs)  
✓ Integrates seamlessly with Kubernetes  
✓ Supports multiple deployment models  
✓ Includes comprehensive load balancing  

**Next Steps:**
1. Review the Quick Reference guide
2. Deploy to your Kubernetes cluster
3. Configure CEGP console with relay IP
4. Send test message to verify integration
5. Monitor with Prometheus dashboard
6. Scale as needed (HPA handles automatically)

---

**Document Version:** 3.0 (Complete with Introduction)  
**Last Updated:** March 2025  
**Status:** Production Ready
