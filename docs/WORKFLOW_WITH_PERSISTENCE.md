# CEGP SMTP Relay - Complete Workflow with Persistent Storage

## Message Flow: Start to Finish

```
WORKFLOW: Customer Application → CEGP → Relay Container → Destination
═══════════════════════════════════════════════════════════════════════════════

STEP 1: CUSTOMER APPLICATION (Internal System)
──────────────────────────────────────────────────────────────────────────────

   Alice (user@company.com)
         ↓ [SEND in Outlook]
    
   ┌──────────────────────────────┐
   │ Exchange Server / Gmail      │
   │ (on-premises or cloud)       │
   │                              │
   │ COMPOSE EMAIL:               │
   │  From: alice@company.com     │
   │  To: bob@gmail.com           │
   │  Subject: Q2 Report          │
   │  Body: [Confidential data]   │
   │                              │
   │ ROUTE LOGIC:                 │
   │ "Is bob@gmail.com local?"    │
   │ → NO                          │
   │ "Route via CEGP?"            │
   │ → YES                         │
   │                              │
   │ Action: Send to CEGP        │
   │ Target: relay.mx.trendmicro │
   └──────────────────────────────┘
                ↓ SMTP Port 25
           [~1-2 seconds elapsed]


STEP 2: CEGP CLOUD GATEWAY (Trend Micro)
──────────────────────────────────────────────────────────────────────────────

   ┌──────────────────────────────────────────┐
   │ relay.mx.trendmicro.com                  │
   │ (CEGP Endpoint - Cloud)                  │
   │                                          │
   │ RECEIVE MESSAGE:                         │
   │ ├─ SMTP Connection accepted              │
   │ ├─ MAIL FROM: <alice@company.com>       │
   │ ├─ RCPT TO: <bob@gmail.com>             │
   │ ├─ DATA: [Message body + attachments]   │
   │ └─ Received: SMTP 250 OK                │
   │                                          │
   │ THREAT SCANNING:                        │
   │ ├─ Malware scan: ✓ CLEAN                │
   │ ├─ Phishing detection: ✓ SAFE           │
   │ ├─ BEC analysis: ✓ LEGITIMATE           │
   │ ├─ DLP policy: [Financial data detected]│
   │ │  └─ Action: APPROVED (user authorized)│
   │ └─ Attachment handling: ✓ CLEAN         │
   │                                          │
   │ POLICY APPLICATION:                     │
   │ ├─ Add headers:                          │
   │ │  ├─ X-TrendMicro-Scanned: Yes         │
   │ │  ├─ X-TrendMicro-Status: Clean        │
   │ │  └─ X-TrendMicro-Action: Approved     │
   │ ├─ Clean attachments: [PDF OK]          │
   │ └─ Archive copy: [Optional]              │
   │                                          │
   │ OUTBOUND ROUTING:                       │
   │ ├─ Domain: company.com                   │
   │ ├─ Lookup: Type "User-Defined Servers"  │
   │ ├─ Server: relay.email-security.....:25 │
   │ ├─ Preference: 10 (primary)             │
   │ └─ Action: Forward scanned message      │
   └──────────────────────────────────────────┘
                ↓ SMTP Port 25
           [~1-2 seconds elapsed]
           Total so far: 2-4 seconds


STEP 3: RELAY CONTAINER - INBOUND ACCEPTANCE
──────────────────────────────────────────────────────────────────────────────

   ┌────────────────────────────────────────────────────────────┐
   │ Kubernetes Pod: cegp-smtp-relay-abc123                     │
   │ (Relay Container - Your Infrastructure)                    │
   │                                                             │
   │ SMTP LISTENER (Port 25):                                  │
   │ ├─ Receives connection from CEGP                          │
   │ ├─ EHLO greeting exchange                                 │
   │ └─ MAIL FROM / RCPT TO / DATA exchange                    │
   │                                                             │
   │ POLICY VALIDATION (via Policy Daemon):                   │
   │                                                             │
   │ Check #1: Source IP Authorization                         │
   │ ├─ CEGP IP: 150.70.149.5                                 │
   │ ├─ permit-ips.conf: Contains 150.70.149.0/27             │
   │ └─ Result: ✓ PASS                                         │
   │                                                             │
   │ Check #2: Sender Domain Whitelist                         │
   │ ├─ MAIL FROM: <alice@company.com>                        │
   │ ├─ Domain: company.com                                    │
   │ ├─ domains.conf: Contains "company.com"                  │
   │ └─ Result: ✓ PASS                                         │
   │                                                             │
   │ Check #3: Rate Limiting (Per CEGP IP)                   │
   │ ├─ Token Bucket (Redis): 150.70.149.5                   │
   │ ├─ Current: 234 msg/min from this IP                    │
   │ ├─ Limit: 2,000 msg/min per IP                          │
   │ ├─ Status: 234 < 2000 ✓ PASS                            │
   │ └─ Action: Consume 1 token                                │
   │                                                             │
   │ Check #4: Rate Limiting (Per Recipient)                 │
   │ ├─ Token Bucket (Redis): bob@gmail.com                  │
   │ ├─ Current: 45 msg/min to this recipient               │
   │ ├─ Limit: 200 msg/min per recipient                    │
   │ ├─ Status: 45 < 200 ✓ PASS                             │
   │ └─ Action: Consume 1 token                               │
   │                                                             │
   │ Check #5: Message Size                                   │
   │ ├─ Message size: 245 KB                                 │
   │ ├─ Limit: 50 MB (52,428,800 bytes)                      │
   │ └─ Result: 245 KB < 50 MB ✓ PASS                       │
   │                                                             │
   │ Check #6: Recipient Count                                │
   │ ├─ Recipients: 1 (bob@gmail.com)                         │
   │ ├─ Limit: 99,999                                        │
   │ └─ Result: 1 < 99,999 ✓ PASS                           │
   │                                                             │
   │ ALL CHECKS PASSED! ✓                                      │
   │                                                             │
   │ RESPONSE TO CEGP:                                        │
   │ ├─ SMTP Code: 250 OK                                    │
   │ ├─ Message: "Message queued for delivery"               │
   │ └─ CEGP closes connection                                │
   │                                                             │
   └────────────────────────────────────────────────────────────┘
                ↓
           [0.5 seconds elapsed]


STEP 4: RELAY CONTAINER - MESSAGE PERSISTENCE
──────────────────────────────────────────────────────────────────────────────

   ┌────────────────────────────────────────────────────────────┐
   │ Postfix Queue Manager                                      │
   │                                                             │
   │ MESSAGE QUEUEING:                                         │
   │ ├─ Queue directory: /var/spool/postfix/                  │
   │ │  └─ Mount: PersistentVolumeClaim (EBS Volume)          │
   │ │                                                          │
   │ │  Directory structure:                                   │
   │ │  ├─ active/    (being processed)                       │
   │ │  ├─ bounce/    (NDR messages)                          │
   │ │  ├─ defer/     (messages awaiting retry) ← HERE        │
   │ │  ├─ incoming/  (new messages)                          │
   │ │  ├─ maildrop/  (local drops)                           │
   │ │  ├─ pid/       (process IDs)                           │
   │ │  ├─ private/   (sockets)                               │
   │ │  ├─ public/    (sockets)                               │
   │ │  └─ saved/     (archived)                              │
   │ │                                                          │
   │ ├─ Create message file:                                   │
   │ │  └─ File: /var/spool/postfix/defer/ABC123...          │
   │ │     ├─ Content: Full message + headers                 │
   │ │     ├─ Metadata: From, To, Retry count                │
   │ │     └─ Size: 245 KB                                    │
   │ │                                                          │
   │ ├─ Sync to disk (Postfix guarantees):                    │
   │ │  ├─ File written                                       │
   │ │  ├─ fsync() called (data on disk)                      │
   │ │  └─ EBS volume: Message persisted ✓                    │
   │ │                                                          │
   │ └─ Status: Ready for delivery                             │
   │                                                             │
   │ KUBERNETES GUARANTEE:                                    │
   │ ├─ PVC: Mounted at /var/spool/postfix/                  │
   │ ├─ PV: EBS volume (AWS) - durable storage               │
   │ ├─ Replication: By AWS (3x within region)                │
   │ ├─ Data at rest: Encrypted (optional KMS)               │
   │ └─ Availability: 99.9% uptime SLA                        │
   │                                                             │
   └────────────────────────────────────────────────────────────┘
                ↓
           [0.1 seconds elapsed]
           Total so far: 3-5 seconds


STEP 5: RELAY CONTAINER - OUTBOUND DELIVERY
──────────────────────────────────────────────────────────────────────────────

   ┌────────────────────────────────────────────────────────────┐
   │ Postfix Delivery Agent                                     │
   │                                                             │
   │ MESSAGE DELIVERY:                                         │
   │ ├─ Read message from queue:                               │
   │ │  └─ File: /var/spool/postfix/defer/ABC123...           │
   │ │                                                          │
   │ ├─ Parse destination:                                    │
   │ │  └─ RCPT TO: <bob@gmail.com>                          │
   │ │     ├─ Local part: bob                                 │
   │ │     └─ Domain: gmail.com                               │
   │ │                                                          │
   │ ├─ DNS MX Lookup for gmail.com:                          │
   │ │  ├─ Query: gmail.com MX                                │
   │ │  └─ Response:                                          │
   │ │     ├─ Priority 5: gmail-smtp-in.l.google.com         │
   │ │     │  └─ IP: 142.251.41.5                            │
   │ │     ├─ Priority 10: alt1.gmail-smtp-in...             │
   │ │     │  └─ IP: 142.251.40.5                            │
   │ │     └─ Priority 20: alt2.gmail-smtp-in...             │
   │ │        └─ IP: 142.251.41.6                            │
   │ │                                                          │
   │ ├─ Connect to Primary Server:                            │
   │ │  ├─ Server: gmail-smtp-in.l.google.com:25             │
   │ │  ├─ IP: 142.251.41.5:25                               │
   │ │  ├─ Connection: TCP established ✓                      │
   │ │  └─ Time: ~500ms                                       │
   │ │                                                          │
   │ ├─ SMTP Transaction:                                     │
   │ │  ├─ EHLO relay.email-security.svc...                  │
   │ │  │  └─ Response: 250 PONG                              │
   │ │  │                                                      │
   │ │  ├─ MAIL FROM: <alice@company.com>                    │
   │ │  │  └─ Response: 250 OK                                │
   │ │  │                                                      │
   │ │  ├─ RCPT TO: <bob@gmail.com>                          │
   │ │  │  └─ Response: 250 OK                                │
   │ │  │                                                      │
   │ │  ├─ DATA                                               │
   │ │  │  └─ Response: 354 Go ahead                          │
   │ │  │                                                      │
   │ │  ├─ [Message Headers with X-TrendMicro-* tags]       │
   │ │  ├─ [Message Body]                                    │
   │ │  ├─ [Signature: Gmail accepted]                       │
   │ │  │                                                      │
   │ │  ├─ . (End of data)                                    │
   │ │  │  └─ Response:                                       │
   │ │  │     250 Message accepted for delivery               │
   │ │  │     ID: <Gmail-Internal-ID>                         │
   │ │  │                                                      │
   │ │  ├─ QUIT                                               │
   │ │  └─ Connection closed                                  │
   │ │                                                          │
   │ ├─ Message Delivery Result: ✓ SUCCESS                    │
   │ │  ├─ Delivery time: ~1.5 seconds                        │
   │ │  ├─ Status: Delivered                                  │
   │ │  └─ Action: Remove from queue                          │
   │ │                                                          │
   │ └─ Queue Updates:                                        │
   │    ├─ Message deleted from /var/spool/postfix/defer/    │
   │    ├─ Logs updated: delivery_status="success"           │
   │    └─ Metrics updated:                                  │
   │       ├─ relay_messages_delivered_total += 1            │
   │       ├─ relay_delivery_latency_seconds = 2.0s          │
   │       └─ relay_queue_size_messages -= 1                 │
   │                                                           │
   └────────────────────────────────────────────────────────────┘
                ↓
           [~2 seconds elapsed]
           Total so far: 5-7 seconds


STEP 6: FINAL DESTINATION (Internet Mail Server)
──────────────────────────────────────────────────────────────────────────────

   ┌────────────────────────────────────────────────┐
   │ Gmail Server (142.251.41.5)                    │
   │                                                │
   │ RECEIVES MESSAGE:                             │
   │ ├─ SMTP acceptance confirmed                  │
   │ ├─ Message stored in database                 │
   │ ├─ Spam filters applied                       │
   │ ├─ Gmail header: X-TrendMicro-* headers found │
   │ └─ Status: Message in queue for delivery      │
   │                                                │
   │ DELIVERS TO USER:                             │
   │ ├─ bob@gmail.com                              │
   │ ├─ Subject: Q2 Report                         │
   │ ├─ From: alice@company.com                    │
   │ ├─ Headers: Includes X-TrendMicro-Scanned     │
   │ ├─ Body: [Confidential Q2 data] ✓ SAFE       │
   │ └─ Attachments: [PDF report.pdf] ✓ CLEAN     │
   │                                                │
   │ NOTIFICATION:                                 │
   │ └─ Bob receives email notification             │
   │    "New email from alice@company.com"         │
   │                                                │
   └────────────────────────────────────────────────┘


TOTAL MESSAGE JOURNEY TIME: 5-10 seconds
═════════════════════════════════════════════════════════════════════════════════

Timeline:
  Time 0s:    Alice clicks SEND
  Time 1-2s:  Message reaches CEGP
  Time 2-4s:  CEGP scans and forwards to relay
  Time 4-5s:  Relay validates and queues message
  Time 5-7s:  Relay delivers to Gmail
  Time 7-10s: Bob receives email

Result: ✅ ZERO MESSAGE LOSS (saved on PVC)
        ✅ MESSAGE DELIVERED END-TO-END
        ✅ COMPLETE AUDIT TRAIL
```

---

## Disaster Recovery: Container Restart Scenario

```
SCENARIO: Pod Crash During Message Processing
═══════════════════════════════════════════════════════════════════════════════

BEFORE CRASH (14:32:00)
──────────────────────────

Relay Pod: cegp-smtp-relay-abc123
├─ Status: Running ✓
├─ Queue Messages: 5,000
│  ├─ In progress: 1,200
│  ├─ Queued: 3,800
│  └─ Location: /var/spool/postfix/ (PVC - PERSISTENT) ✓
│
├─ PersistentVolume:
│  ├─ Type: EBS (AWS)
│  ├─ Size: 100 GB
│  ├─ Used: 15.3 GB
│  ├─ Data: Safely replicated ✓
│  └─ Status: Healthy
│
└─ Metrics:
   ├─ CPU: 35%
   ├─ Memory: 620 MB
   ├─ Messages delivered: 15,234
   └─ Queue size: 5,000


POD CRASH (14:32:45)
────────────────────

Incident: Memory leak → OOMKilled

Kubernetes Actions (Automatic):
├─ Detect pod crash
├─ Initiate graceful shutdown (60 second grace period)
├─ Signal Postfix: Stop accepting new messages
├─ Wait for in-flight messages to finish
├─ Flush queue to disk ✓
├─ Sync /var/spool/postfix/ → EBS volume ✓
├─ At 60s: Force terminate pod
└─ Messages on EBS: SAFE ✓


RECOVERY (14:33:45 onwards)
────────────────────────────

Step 1: Kubernetes Detects Pod Missing (30s)
├─ Liveness probe fails
├─ Create new pod: cegp-smtp-relay-def456
└─ Status: Pending

Step 2: Schedule New Pod (15s)
├─ Select healthy node
├─ Reserve resources (CPU, memory)
├─ Request PVC attachment
└─ Status: ContainerCreating

Step 3: Mount PVC & Start Container (30s)
├─ Attach EBS volume to node
├─ Mount at /var/spool/postfix/
├─ Pull container image
├─ Start Postfix process
├─ Queue Manager scans directory
├─ Found 5,000 queued messages ✓
└─ Resume delivery

Step 4: Pod Ready (Total 75s)
├─ Liveness probe: PASS ✓
├─ Readiness probe: PASS ✓
├─ Status: Running & Ready
└─ Postfix: Delivering queued messages


DELIVERY RECOVERY
─────────────────

Message Recovery:
├─ Postfix reads from /var/spool/postfix/defer/
├─ Finds all 5,000 messages intact ✓
├─ Resume SMTP connections
├─ Begin delivery attempts
└─ Process in sequence

Timeline:
  14:32:45 → Pod crashes
  14:33:45 → New pod created
  14:34:00 → Pod running & mounting PVC
  14:34:30 → Pod ready, delivery resuming
  14:35:00 → 3,000 messages delivered ✓
  14:36:00 → 5,000 messages delivered ✓
  14:37:00 → Queue clear, no failures ✓


RESULT: ✅ ZERO MESSAGE LOSS
        ✅ AUTOMATIC RECOVERY (NO MANUAL ACTION)
        ✅ ~5 MINUTE TOTAL RECOVERY
        ✅ NO CUSTOMER IMPACT (Messages queued at CEGP)
```

---

## Key Points: Persistent Storage

```
┌─────────────────────────────────────────────────────────────┐
│ WHY PERSISTENT STORAGE MATTERS                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ Without Persistent Storage:                                │
│ ├─ Pod crash → Message queue deleted                       │
│ ├─ 5,000 queued messages → LOST ✗                         │
│ ├─ Customers affected → Need to resend                     │
│ └─ SLA violation → 99.99% → 99.9%                         │
│                                                              │
│ With Persistent Storage (This Solution):                   │
│ ├─ Pod crash → Message queue survives                      │
│ ├─ 5,000 queued messages → SAFE ✓                         │
│ ├─ Customers not affected → Auto-recovery                  │
│ ├─ SLA maintained → 99.99% uptime ✓                       │
│ └─ Zero message loss → Guaranteed ✓                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

**Deployment Option:** Use `kubernetes-deployment-persistent.yaml` for production  
**Storage:** EBS (AWS), Persistent Disk (GCP), or Local volumes  
**Cost:** ~$10-30/month for 100GB SSD  
**Recovery Time:** Automatic, 2-5 minutes  
**Message Loss Risk:** ZERO ✅

---

**Document Version:** 1.0  
**Last Updated:** March 2025  
**Status:** Production Ready
