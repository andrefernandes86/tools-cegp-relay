# CEGP Relay Architecture - Visual Reference

## Diagram 1: High-Level Architecture with CEGP Integration

```
┌──────────────────────────────────────────────────────────────────────────┐
│ CUSTOMER ENVIRONMENT                                                     │
│                                                                          │
│  ┌──────────────────────────┐                                           │
│  │  Mail Clients & Apps     │                                           │
│  │  (Outlook, Gmail, etc)   │                                           │
│  └────────────┬─────────────┘                                           │
│               │ compose & send                                          │
│               ▼                                                         │
│  ┌──────────────────────────────────────────┐                          │
│  │  Exchange / Google Workspace             │                          │
│  │  On-Premises Mail Server                 │                          │
│  │  (Mail Store & Routing Logic)            │                          │
│  └────────────┬─────────────────────────────┘                          │
│               │                                                         │
│               │ Route outbound mail to:                                 │
│               │ relay.mx.trendmicro.com (CEGP)                         │
│               │                                                         │
└───────────────┼─────────────────────────────────────────────────────────┘
                │
                │ INTERNET
                │ Port 25 (SMTP)
                │
┌───────────────▼──────────────────────────────────────────────────────────┐
│ TREND MICRO CEGP CLOUD                                                   │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ relay.mx.trendmicro.com (Regional Endpoint)                        │  │
│  │                                                                     │  │
│  │  1. Inbound SMTP Connection (from customer mail server)            │  │
│  │  2. Message Scanning                                               │  │
│  │     - Threat engine (malware, phishing, ransomware)                │  │
│  │     - BEC (Business Email Compromise) detection                    │  │
│  │     - DLP (Data Loss Prevention) rules                             │  │
│  │     - Spam filtering                                               │  │
│  │  3. Policy Actions                                                 │  │
│  │     - Quarantine / Clean / Modify headers                          │  │
│  │  4. Outbound Server Resolution                                     │  │
│  │     - Lookup domain configuration: company.com                     │  │
│  │     - Find: "User-Defined Mail Servers"                            │  │
│  │     - Retrieve outbound server list (preference-ordered)           │  │
│  │  5. Forward to Relay Container                                     │  │
│  │                                                                     │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
└───────────────┬──────────────────────────────────────────────────────────┘
                │
                │ Scanned message to:
                │ [Relay Container] (port 25)
                │ (CUSTOMER'S INTERNAL NETWORK)
                │
┌───────────────▼──────────────────────────────────────────────────────────┐
│ KUBERNETES CLUSTER (Customer Datacenter)                                  │
│                                                                           │
│ Namespace: email-security                                                │
│                                                                           │
│ ┌─────────────────────────────────────────────────────────────────────┐  │
│ │ Service: cegp-smtp-relay (LoadBalancer, IP: 203.0.113.100)          │  │
│ │                                                                      │  │
│ │ ┌─ Pod 1 ────────────────────────────────────────────────────────┐  │  │
│ │ │ CEGP Relay Container                                          │  │  │
│ │ │                                                                │  │  │
│ │ │  ┌─────────────────────────────────────────────────────────┐  │  │  │
│ │ │  │ SMTP Server (Postfix on port 25)                        │  │  │  │
│ │ │  │ ┌───────────────────────────────────────────────────┐   │  │  │  │
│ │ │  │ │ RECEIVE from CEGP:                               │   │  │  │  │
│ │ │  │ │  1. Validate source IP (permit-ips.conf)         │   │  │  │  │
│ │ │  │ │  2. Validate sender domain (domains.conf)        │   │  │  │  │
│ │ │  │ │  3. Check message size (50MB limit)              │   │  │  │  │
│ │ │  │ │  4. Rate limit: 2000 msg/min per CEGP IP        │   │  │  │  │
│ │ │  │ │  5. Rate limit: 200 msg/min per recipient        │   │  │  │  │
│ │ │  │ │  6. Queue message to /var/spool/postfix/         │   │  │  │  │
│ │ │  │ │  7. Return 250 OK to CEGP                        │   │  │  │  │
│ │ │  │ └───────────────────────────────────────────────────┘   │  │  │  │
│ │ │  │                          ▼                               │  │  │  │
│ │ │  │ ┌───────────────────────────────────────────────────┐   │  │  │  │
│ │ │  │ │ DELIVER to Final Destination:                    │   │  │  │  │
│ │ │  │ │  1. DNS MX lookup (gmail.com → 142.251.41.5)    │   │  │  │  │
│ │ │  │ │  2. Connect to destination SMTP server           │   │  │  │  │
│ │ │  │ │  3. Send message (already scanned by CEGP)       │   │  │  │  │
│ │ │  │ │  4. Handle bounce/retry if destination down      │   │  │  │  │
│ │ │  │ │  5. Log delivery success/failure                 │   │  │  │  │
│ │ │  │ │  6. Export metrics to Prometheus                 │   │  │  │  │
│ │ │  │ └───────────────────────────────────────────────────┘   │  │  │  │
│ │ │  └─────────────────────────────────────────────────────────┘  │  │  │
│ │ │                                                                │  │  │
│ │ │  ┌─────────────────────────────────────────────────────────┐  │  │  │
│ │ │  │ Policy Daemon (Python)                                 │  │  │  │
│ │ │  │  - Enforces domain whitelist (CEGP side)               │  │  │  │
│ │ │  │  - Rate limiting with Redis token bucket               │  │  │  │
│ │ │  │  - Connection ACL (CEGP IP ranges only)                │  │  │  │
│ │ │  └─────────────────────────────────────────────────────────┘  │  │  │
│ │ │                                                                │  │  │
│ │ │  ┌─────────────────────────────────────────────────────────┐  │  │  │
│ │ │  │ Monitoring (port 9090)                                 │  │  │  │
│ │ │  │  - /health endpoint (Kubernetes liveness/readiness)    │  │  │  │
│ │ │  │  - /metrics endpoint (Prometheus scrape)               │  │  │  │
│ │ │  │  - Structured JSON logging to stdout                  │  │  │  │
│ │ │  └─────────────────────────────────────────────────────────┘  │  │  │
│ │ └────────────────────────────────────────────────────────────┘  │  │  │
│ │                                                                   │  │  │
│ │ ┌─ Pod 2 ────────────────────────────────────────────────────┐  │  │  │
│ │ │ CEGP Relay Container (identical to Pod 1)                │  │  │  │
│ │ └────────────────────────────────────────────────────────────┘  │  │  │
│ │                                                                   │  │  │
│ │ ┌─ Pod 3 ────────────────────────────────────────────────────┐  │  │  │
│ │ │ CEGP Relay Container (identical to Pod 1)                │  │  │  │
│ │ └────────────────────────────────────────────────────────────┘  │  │  │
│ │                                                                   │  │  │
│ │ HPA: Scales to 3-20 pods based on CPU (70%) & Memory (75%)      │  │  │
│ │                                                                   │  │  │
│ └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│ ┌─────────────────────────────────────────────────────────────────┐  │
│ │ ConfigMaps:                                                      │  │
│ │  - postfix-config → main.cf, master.cf                         │  │
│ │  - relay-policy → domains.conf, permit-ips.conf                │  │
│ │                                                                  │  │
│ │ Secrets:                                                        │  │
│ │  - relay-tls-certs → TLS certificates (if needed)              │  │
│ │                                                                  │  │
│ │ Storage:                                                        │  │
│ │  - emptyDir: /var/spool/postfix/ (transient queue)             │  │
│ │  - emptyDir: /var/log/relay/ (container logs)                  │  │
│ │                                                                  │  │
│ └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
└───────────────┬───────────────────────────────────────────────────────┘
                │
                │ OUTBOUND DELIVERY
                │ (to any Internet mail server)
                │
┌───────────────▼───────────────────────────────────────────────────────┐
│ FINAL DESTINATION MAIL SERVERS                                         │
│                                                                        │
│  ┌─────────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │ Gmail           │  │ Outlook.com  │  │ Corporate    │             │
│  │ (Google)        │  │ (Microsoft)  │  │ Mail Server  │             │
│  └─────────────────┘  └──────────────┘  └──────────────┘             │
│                                                                        │
│  Message delivered with:                                              │
│  ✓ Original sender/recipient intact                                  │
│  ✓ CEGP scan headers added                                           │
│  ✓ Safe attachments (cleaned/sandboxed)                              │
│  ✓ DLP rules applied                                                 │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Diagram 2: Message State Transitions

```
                    ┌──────────────────────────┐
                    │  1. CUSTOMER COMPOSES    │
                    │  User @ Outlook/Gmail    │
                    └────────────┬─────────────┘
                                 │
                    ┌────────────▼──────────┐
                    │ 2. MAIL STORE QUEUE   │
                    │ Exchange/Gmail Store  │
                    └────────────┬──────────┘
                                 │
                    ┌────────────▼──────────────────┐
                    │ 3. OUTBOUND ROUTING          │
                    │ Route to: relay.mx.trendmicro│
                    └────────────┬──────────────────┘
                                 │
                    ┌────────────▼──────────────────┐
                    │ 4. CEGP GATEWAY INBOUND      │
                    │ Port 25: Accept message     │
                    │ Log: relay_messages_received │
                    └────────────┬──────────────────┘
                                 │
                    ┌────────────▼──────────────────┐
                    │ 5. THREAT SCANNING (CEGP)   │
                    │ Malware, Phishing, BEC, DLP │
                    │ Policy Actions Applied      │
                    │ Headers Modified             │
                    └────────────┬──────────────────┘
                                 │
                    ┌────────────▼──────────────────┐
                    │ 6. OUTBOUND RESOLUTION      │
                    │ Domain: company.com          │
                    │ Type: User-Defined Servers  │
                    │ Server: relay container:25  │
                    └────────────┬──────────────────┘
                                 │
                    ┌────────────▼──────────────────┐
                    │ 7. RELAY INBOUND ACCEPT     │
                    │ SMTP 250 OK Message Queued  │
                    │ Postfix /var/spool/postfix/ │
                    │ Log: relay_messages_queued   │
                    └────────────┬──────────────────┘
                                 │
                    ┌────────────▼──────────────────┐
                    │ 8. RATE LIMIT CHECK         │
                    │ Per CEGP IP: 2000/min       │
                    │ Per recipient: 200/min      │
                    │ Passed: Continue            │
                    │ Exceeded: Defer (4xx)       │
                    └────────────┬──────────────────┘
                                 │
                    ┌────────────▼──────────────────┐
                    │ 9. POLICY VALIDATION        │
                    │ Sender domain in whitelist? │
                    │ Message size < 50MB?        │
                    │ Recipients < 99,999?        │
                    │ All pass: Queue             │
                    │ Fail: Reject (550)          │
                    └────────────┬──────────────────┘
                                 │
                    ┌────────────▼──────────────────┐
                    │ 10. DNS MX LOOKUP           │
                    │ Destination: bob@gmail.com  │
                    │ Query: gmail.com MX record  │
                    │ Result: 142.251.41.5:25    │
                    └────────────┬──────────────────┘
                                 │
                    ┌────────────▼──────────────────┐
                    │ 11. OUTBOUND DELIVER        │
                    │ Connect to gmail.com:25      │
                    │ Send SMTP transaction        │
                    │ 250 OK = Accepted            │
                    └────────────┬──────────────────┘
                                 │
                    ┌────────────▼──────────────────┐
                    │ 12. FINAL DELIVERY           │
                    │ Gmail processes message      │
                    │ Delivered to bob@gmail.com   │
                    │ Log: relay_messages_delivered│
                    └──────────────────────────────┘
```

---

## Diagram 3: Data Flow - CEGP to Relay Container

```
CEGP Perspective                  Relay Container Perspective
══════════════════════════════════════════════════════════════

Step 1: Domain Configuration
─────────────────────────────
┌─────────────────────────┐
│ CEGP Console:           │
│ Add Domain: company.com │
│ Outbound: User Servers  │
│ Server IP: <relay-ip>   │
│ Port: 25                │
│ Preference: 10          │
└────────────┬────────────┘
             │
    Configuration
    takes effect
             │
             ▼
         ┌─────────────────┐
         │ CEGP Readiness  │
         │ Ready to relay  │
         └─────────────────┘


Step 2: Customer Sends Outbound
───────────────────────────────
┌──────────────────────┐
│ Customer Mail Server │
│ MAIL FROM: user@...  │
│ RCPT TO: bob@gm...   │
│ DATA: Message body   │
└──────────┬───────────┘
           │ SMTP
           ▼
     ┌──────────────┐
     │ CEGP Gateway │
     │ Accept msg   │
     │ Queue: scan  │
     └──────────────┘


Step 3: CEGP Scanning
────────────────────
┌──────────────────────────┐
│ Threat Engine Runs:      │
│ ✓ Malware scan           │
│ ✓ Phishing detection     │
│ ✓ DLP policy check       │
│ ✓ BEC analysis           │
│ Headers modified         │
│ Attachments cleaned      │
└──────────┬───────────────┘
           │ Message
           │ processed
           ▼
    ┌─────────────────────┐
    │ Outbound Resolution │
    │ Lookup: company.com │
    │ → User-Defined      │
    │ → relay-ip:25       │
    └──────────┬──────────┘


Step 4: Forward to Relay
───────────────────────                ┌──────────────────────┐
                                       │ Relay Container      │
┌──────────────────────┐                │ (cegp-smtp-relay)    │
│ CEGP Connects:       │                │                      │
│ Server: relay-ip:25  │    TCP ───►   │ Listening on Port 25 │
│ EHLO relay-mx        │    :25        │                      │
└──────────┬───────────┘                └──────────┬───────────┘
           │                                       │
    Send Scanned Message                  Accept & Validate
           │                                       │
           ├── MAIL FROM: user@company  ────►   ├─ Check Source IP
           │   (CEGP verifies sender)              │  permit-ips.conf
           │                                       │  ✓ PASS
           ├── RCPT TO: bob@gmail.com  ────►   ├─ Check Sender Domain
           │   (CEGP tracks recipient)             │  domains.conf
           │                                       │  ✓ company.com PASS
           ├── DATA                    ────►   ├─ Check Message Size
           │   (Full message+headers)              │  < 50MB ✓ PASS
           │   X-TrendMicro-Scanned: Yes          │
           │   X-TrendMicro-Action: Clean         ├─ Rate Limit IP
           │                                       │  2000/min ✓ PASS
           │                                       │
           │                                       ├─ Rate Limit Rcpt
           │                                       │  200/min ✓ PASS
           │                                       │
           │                                       ├─ Queue Message
           │                                       │  /var/spool/postfix/
           │                                       │
           ◄───── SMTP 250 OK Returned ─────────  │
                  "Message accepted"               │
                                                   │ Message in queue
                                                   ▼
                                           ┌──────────────────┐
                                           │ Relay Processing │
                                           │ (Background)     │
                                           └──────────────────┘


Step 5: Relay Delivers to Final Destination
────────────────────────────────────────────

Relay Container                         Final Destination
┌──────────────────────────┐           ┌──────────────────┐
│ Queue Manager Processes  │           │ Gmail Server     │
│ Message: user@...→bob@.. │           │                  │
│                          │           │                  │
│ 1. DNS MX Lookup:        │  SMTP    │                  │
│    gmail.com → 142...    │ :25  ───►  Accepts message  │
│                          │           │                  │
│ 2. Connect & Send SMTP   │  SMTP    │ 250 OK           │
│    MAIL FROM: user@...   │ :25  ◄──  Message delivered │
│    RCPT TO: bob@gmail    │           │                  │
│    DATA (w/ CEGP headers)│           │                  │
│                          │           │                  │
│ 3. Receive: 250 OK       │           │                  │
│    Delivery confirmed    │           │                  │
│                          │           └──────────────────┘
│ 4. Log to Prometheus:    │
│    relay_messages_       │
│    delivered_total       │
│                          │
│ 5. Message Archived:     │
│    Removed from queue    │
│    Complete delivery     │
│                          │
└──────────────────────────┘
```

---

## Diagram 4: CEGP Console Domain Configuration

```
┌────────────────────────────────────────────────────────────┐
│ TrendAI Vision One Cloud Email Gateway Protection Console  │
│                                                             │
│ Email and Collaboration Security Operations               │
│ └─ Cloud Email Gateway Protection                         │
│    └─ DOMAINS                                              │
│                                                             │
│ ┌──────────────────────────────────────────────────────┐   │
│ │ Domains List                                         │   │
│ │ ┌─────────────────────────────────────────────────┐  │   │
│ │ │ Domain Name    │ Outbound Server Type           │  │   │
│ │ ├─────────────────────────────────────────────────┤  │   │
│ │ │ example.org    │ Office 365                     │  │   │
│ │ │ test.local     │ Google Workspace               │  │   │
│ │ │ company.com    │ User-defined mail servers ◄──┐ │  │   │
│ │ └─────────────────────────────────────────────────┘  │   │
│ │                                                        │   │
│ │ [Add Domain] [Edit] [Delete]                          │   │
│ └────────────────────────────────────────────────────────┘   │
│                                                              │
│ Click on company.com to configure Outbound Servers:        │
│                                                              │
│ ┌──────────────────────────────────────────────────────┐    │
│ │ Domain: company.com                                  │    │
│ │ Type: User-defined mail servers                      │    │
│ │                                                       │    │
│ │ OUTBOUND SERVERS CONFIGURATION                       │    │
│ │                                                       │    │
│ │ Primary Server:                                       │    │
│ │ ┌─────────────────────────────────────────────────┐  │    │
│ │ │ Recipient:  [*______________________]          │  │    │
│ │ │ IP/FQDN:    [relay.email-security.            │  │    │
│ │ │             svc.cluster.local__________]       │  │    │
│ │ │ Port:       [25_]                              │  │    │
│ │ │ Preference: [10_] (lower=higher priority)      │  │    │
│ │ │                                                 │  │    │
│ │ │ [Test Connection] [Delete]                      │  │    │
│ │ └─────────────────────────────────────────────────┘  │    │
│ │                                                       │    │
│ │ Secondary Server (Optional Failover):                │    │
│ │ ┌─────────────────────────────────────────────────┐  │    │
│ │ │ Recipient:  [*______________________]          │  │    │
│ │ │ IP/FQDN:    [backup-relay.company.local_]      │  │    │
│ │ │ Port:       [25_]                              │  │    │
│ │ │ Preference: [20_] (higher=fallback)            │  │    │
│ │ │                                                 │  │    │
│ │ │ [Test Connection] [Delete]                      │  │    │
│ │ └─────────────────────────────────────────────────┘  │    │
│ │                                                       │    │
│ │ Send Test Message to: [admin@company.com________]    │    │
│ │ [Send Test] [Test Connections]                       │    │
│ │                                                       │    │
│ │ [Save] [Cancel]                                      │    │
│ └──────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘

When you click [Send Test]:

1. CEGP generates a test message
   FROM: donotreply@cegp.trendmicro.com
   TO: admin@company.com

2. CEGP applies scans (malware, phishing, etc.)

3. CEGP looks up domain company.com in its database
   Finds: User-defined mail servers
   Gets: [relay.email-security.svc.cluster.local:25]

4. CEGP connects to relay container at port 25

5. Relay accepts message:
   - Validates CEGP IP is in permit-ips.conf
   - Validates domain company.com is in domains.conf
   - Queues message for delivery

6. Relay looks up admin@company.com:
   - Performs DNS MX for company.com
   - Finds your mail server

7. Relay delivers to your mail server

8. Your mail server delivers to admin's inbox

9. You receive test message with:
   X-TrendMicro-Scanned: Yes
   X-TrendMicro-Action: Clean

Result: ✓ Integration working!
```

---

## Diagram 5: Rate Limiting - Per Spec

```
CEGP SENDING LIMIT                   RELAY CONTAINER LIMIT
═════════════════════════════════════════════════════════════

2,000 messages/minute               2,000 messages/minute
per sender IP                       per sender IP (CEGP's IP)

Timeline: 60 second window

Second  0: ├ Message 1 ✓
Second  1: ├ Message 2 ✓
Second  2: ├ Message 3 ✓
    ...
Second 30: ├ Message 1000 ✓
Second 31: ├ Message 1001 ✓
    ...
Second 59: ├ Message 2000 ✓

Second 60: ├ Message 2001 ◄── RATE LIMIT HIT
           │ CEGP receives: 452 Service temporarily unavailable
           │ CEGP retries later
           │
           │ Meanwhile:
           │ - Message 1 expires from window (removed)
           │ - Tokens replenish
           │ - Message 2001 can be retried

┌─────────────────────────────────────────────────┐
│ Per-Recipient Limit: 200 msg/min                │
├─────────────────────────────────────────────────┤
│                                                  │
│ If CEGP sends 150 msg/min to alice@company.com │
│ and 100 msg/min to bob@company.com:             │
│ ✓ Both succeed (each < 200/min)                 │
│                                                  │
│ If CEGP tries to send 250 msg/min to           │
│ charlie@company.com:                            │
│ - First 200 accepted ✓                          │
│ - Message 201-250: DEFERRED (452)               │
│ - CEGP retries exponentially                    │
│                                                  │
└─────────────────────────────────────────────────┘

QUEUE BACKLOG SCENARIO
──────────────────────

Normal Load:                    Spike Load (After CEGP Scan):
┌─────────┐                     ┌──────────────┐
│ Queue   │ 0-50 messages       │ Queue        │ 5,000+ messages
│ Size    │ (healthy)           │ Size         │ (all within rate limits
└─────────┘                     └──────────────┘  but backing up)

Action: HPA detects high CPU/memory
Result: Scale from 3 → 10 pods
Outcome: Queue processes 3x faster
         Back to normal within 5 minutes
```

---

**Document Version:** 1.0  
**Last Updated:** March 2025
