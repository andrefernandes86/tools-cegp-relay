# CEGP SMTP Relay - "User-Defined Mail Servers" Integration Guide

## Executive Summary

This document defines the complete architectural integration for deploying a containerized SMTP relay service that acts as the **"User-Defined Mail Servers"** endpoint in TrendAI Vision One Cloud Email Gateway Protection (CEGP).

When CEGP is configured with the "User-Defined Mail Servers" outbound option for a managed domain, all scanned outbound messages are relayed to the mail servers you specify. This relay container serves as that endpoint.

---

## 1. CEGP Configuration Context: User-Defined Mail Servers

### 1.1 What is "User-Defined Mail Servers"?

User-defined mail servers: Relays your outbound messages from the mail servers you specified for your managed domain.

In the CEGP console, when adding a domain, you select one of three outbound relay options:
1. **Microsoft 365** - Relays to Office 365
2. **Google Workspace** - Relays to Google Workspace
3. **User-Defined Mail Servers** - Relays to your internal/on-premises mail servers (like this container)

### 1.2 Domain Configuration in CEGP Console

When you select "User-Defined Mail Servers" in CEGP and add a domain (e.g., `company.com`), you must specify:

**Outbound Servers Configuration:**
- IP address or FQDN: Fully qualified domain name (FQDN) is a unique name, which includes both host name and domain name, and resolves to a single IP address. Port: Port is a number from 1 to 65535 that an inbound server listens on
- Preference: Preference, sometimes referred to as distance, is a value from 1 to 100. The lower the preference value, the higher the priority
- You can specify up to 30 inbound servers and 30 outbound servers

### 1.3 Outbound Server Delivery Logic

CEGP routes scanned outbound messages to your user-defined mail servers in priority order:
- Messages are delivered to the outbound server with the **lowest preference value** first
- If that server is unavailable, CEGP fails over to the next server (higher preference)
- Each outbound server can have different recipients (e.g., `recipient1@company.com` → Server-A, `*@company.com` → Server-B)

---

## 2. Relay Container Architecture

### 2.1 Message Flow: Inbound to Outbound

```
┌─────────────────────────────────────────────────────────┐
│ Customer Application/Mail Server (Internal)             │
│ - Exchange, Google Workspace, On-Premise Server         │
│ - Sends outbound mail                                   │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│ CEGP Cloud Gateway (relay.mx.trendmicro.com)            │
│ - Receives outbound messages                            │
│ - Scans for threats (phishing, malware, BEC, DLP)      │
│ - Applies policies & rules                              │
│ - Routes scanned messages to user-defined servers       │
└──────────────────────┬──────────────────────────────────┘
                       │
        Scanned outbound messages
        (headers modified, attachments cleaned)
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│ This Relay Container (cegp-smtp-relay)                  │
│ (Specified in CEGP console as outbound server)          │
│                                                          │
│ ┌─ SMTP Server (Postfix)                              │
│ ├─ Receives scanned messages from CEGP                 │
│ ├─ Validates sender domain                             │
│ ├─ Enforces rate limits                                │
│ ├─ Message size & recipient checks                     │
│ └─ Forwards to destination mail servers                │
│                                                          │
│ Metrics & Logging (Prometheus, syslog)                 │
└──────────────────────┬──────────────────────────────────┘
                       │
      Relayed to final recipient's mail server
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│ Final Recipient Mail Server                             │
│ - Exchange, Gmail, Local IMAP, etc.                     │
│ - Message delivered to user inbox                       │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Why a Relay Container?

The container acts as a **trusted intermediary** that:

1. **Accepts** scanned messages from CEGP (only CEGP is authorized to send to it)
2. **Validates** that the sender domain is permitted (domain whitelist)
3. **Rate-limits** to prevent CEGP overload or abuse
4. **Transforms** if needed (add headers, modify routing)
5. **Forwards** to the final destination mail server(s) via DNS MX lookup or static routing

**Key Benefit:** Even if CEGP is unavailable, messages can be queued and retried when service resumes (Email Continuity).

---

## 3. CEGP Console Configuration (Trend Micro Side)

### 3.1 Step 1: Add Domain with User-Defined Mail Servers

In CEGP Console → Email and Collaboration Security Operations → Cloud Email Gateway Protection → Domains:

1. Click **"Add Domain"**
2. Enter domain name: `company.com`
3. Set **Outbound Servers** to: **User-defined mail servers**
4. Click **Add Domain**

### 3.2 Step 2: Configure Outbound Server(s)

After domain is added, configure the outbound servers:

**Configuration for this relay container:**

| Field | Value | Notes |
|-------|-------|-------|
| **Recipient** | `*` | Wildcard = all recipients in this domain |
| **IP address/FQDN** | `relay.email-security.svc.cluster.local` (K8s) or `relay.company.local` (DNS) | Must resolve to the relay container service |
| **Port** | `25` | Standard SMTP port |
| **Preference** | `10` | Lower = higher priority. Set this as primary outbound server |

**Optional Failover Server (Secondary):**

| Field | Value | Notes |
|-------|-------|-------|
| **Recipient** | `*` | All recipients (same as primary) |
| **IP address/FQDN** | `backup-relay.company.local` | Secondary relay (if deploying multiple instances) |
| **Port** | `25` | Standard SMTP |
| **Preference** | `20` | Higher value = lower priority (failover) |

### 3.3 Step 3: Test Connection (Optional but Recommended)

CEGP provides a "Send test message" field:
- Enter a test email address
- CEGP will send a test message through your relay container
- Verify it arrives in your mailbox

---

## 4. Relay Container Configuration

### 4.1 Environment Variables for CEGP Integration

```bash
# The relay container does NOT connect outbound to CEGP
# Instead, it RECEIVES messages FROM CEGP and forwards them

# Receiving from CEGP
SMTP_LISTEN_PORT=25                    # Port CEGP connects to
SMTP_LISTEN_ADDRESS=0.0.0.0            # Listen on all interfaces
TLS_ENABLED=false                      # CEGP typically sends unencrypted

# Accepting messages
RELAY_DOMAINS_FILE=/var/lib/relay-policy/domains.conf
MAX_MESSAGE_SIZE=52428800              # 50 MB (per CEGP limits)
MAX_RECIPIENTS=99999                   # Per CEGP policy

# Rate limiting (to prevent abuse from CEGP)
RATE_LIMIT_IP_PER_MIN=2000             # Messages/min per sender IP (CEGP's IP)
RATE_LIMIT_RCPT_PER_MIN=200            # Messages/min per recipient

# Outbound forwarding (to final destination)
FORWARD_VIA_DNS=true                   # Use DNS MX lookup for destinations
FORWARD_PROTOCOL=SMTP                  # Standard SMTP forwarding
FORWARD_TLS_REQUIRED=false              # Adjust based on destination requirements

# Monitoring
PROMETHEUS_PORT=9090
LOG_LEVEL=INFO
```

### 4.2 Relay Domains Configuration

**File:** `/var/lib/relay-policy/domains.conf`

This file contains the domains whose messages the relay will accept FROM CEGP:

```
company.com
subsidiary.org
branch.local
```

When CEGP sends a scanned message for `user@company.com`, the relay validates that `company.com` is in this list before accepting it.

### 4.3 Connection Control: CEGP IP Authorization

**File:** `/var/lib/relay-policy/permit-ips.conf`

This file contains the IP addresses from which the relay accepts connections:

```
# CEGP Regional Endpoints (example IPs from Trend Micro)
150.70.149.0/27
150.70.149.32/27
150.70.236.0/24
150.70.239.0/24
216.99.131.0/24
216.104.4.0/24
216.104.20.0/24

# Or if CEGP is in same cluster
10.0.0.0/8
```

**IMPORTANT:** Only CEGP's IP addresses should be in this list. This prevents unauthorized SMTP injection.

---

## 5. Message Flow & Rate Limiting

### 5.1 Inbound Phase (CEGP → Relay Container)

```
CEGP sends scanned message to relay@port 25

┌─────────────────────────────────┐
│ Relay Container Accepts Message │
├─────────────────────────────────┤
│ 1. Verify sender IP is CEGP     │ → Check permit-ips.conf
│ 2. Check domain is allowed      │ → Check domains.conf
│ 3. Validate message size        │ → Max 50MB
│ 4. Validate recipient count     │ → Max 99,999
│ 5. Rate limit per CEGP IP       │ → 2000 msg/min (per spec)
│ 6. Rate limit per recipient     │ → 200 msg/min (per spec)
│ 7. Queue for delivery           │ → Local disk queue
└─────────────────────────────────┘

Response to CEGP:
- 250 OK → Message accepted, queued for delivery
- 452 Service unavailable → Rate limit exceeded (CEGP will retry)
- 550 Relay access denied → Domain not in whitelist (permanent rejection)
```

### 5.2 Outbound Phase (Relay → Destination)

```
Relay Container Delivers to Final Destination

┌─────────────────────────────────┐
│ Outbound Message Delivery       │
├─────────────────────────────────┤
│ 1. Perform DNS MX lookup        │ → Find mail server for domain
│ 2. Connect to destination MX    │ → Port 25 (or configured)
│ 3. Send SMTP transaction        │ → Standard SMTP protocol
│ 4. Receive delivery status      │ → 250 OK or rejection
│ 5. Log delivery result          │ → Prometheus metrics + syslog
│ 6. Mark as delivered/bounced    │ → NDR if rejected
└─────────────────────────────────┘

Responses to Final Destination:
- 250 OK → Message delivered
- 4xx Temporary failure → Retry later
- 5xx Permanent failure → Generate NDR
```

---

## 6. Postfix Configuration for CEGP Integration

### 6.1 Simplified Postfix main.cf

```postfix
# CEGP Relay Container Configuration

# Network & Hostname
myhostname = relay.email-security.svc.cluster.local
mynetworks = 127.0.0.1/32 [::1]/128 150.70.149.0/27 150.70.149.32/27 150.70.236.0/24 150.70.239.0/24
inet_interfaces = all

# Message Limits
message_size_limit = 52428800
recipient_limit = 99999

# CEGP-specific: Disable local delivery
local_transport = error

# Routing
transport_maps = hash:/etc/postfix/transport

# Policy daemon for rate limiting
smtpd_recipient_restrictions =
    permit_mynetworks,
    check_policy_service unix:private/policy-socket,
    permit

# TLS (optional - CEGP typically doesn't require encryption for internal relay)
smtpd_tls_security_level = may
smtpd_tls_cert_file = /etc/certs/relay-cert.pem
smtpd_tls_key_file = /etc/certs/relay-key.pem
```

### 6.2 Transport Map (Optional Routing)

If you have multiple destination servers:

```postfix
# /etc/postfix/transport
company.com        smtp:[mail.company.local]:25
subsidiary.org     smtp:[mail-subsidiary.local]:25
*                  smtp:[default-mail.local]:25
```

---

## 7. Kubernetes Deployment Changes for CEGP Integration

### 7.1 Key Configuration Differences

**INBOUND (from CEGP):**
- Service port 25 exposed to CEGP's IP ranges
- No TLS required (internal relay)
- High throughput expected

**OUTBOUND (to destination):**
- DNS resolution required (MX lookups)
- TLS optional (depends on destination requirements)
- Retry logic for temporary failures

### 7.2 Updated Service Spec

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cegp-smtp-relay
  namespace: email-security
spec:
  type: LoadBalancer  # ← Changed from ClusterIP
                      # CEGP needs external access
  loadBalancerSourceRanges:
    - 150.70.149.0/27
    - 150.70.149.32/27
    - 150.70.236.0/24
    - 150.70.239.0/24
    - 216.99.131.0/24
    - 216.104.4.0/24
    - 216.104.20.0/24
  selector:
    app: cegp-smtp-relay
  ports:
    - name: smtp
      port: 25
      targetPort: 25
      protocol: TCP
```

### 7.3 Network Policy for CEGP

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cegp-inbound-only
  namespace: email-security
spec:
  podSelector:
    matchLabels:
      app: cegp-smtp-relay
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Only CEGP can send to this relay
    - from:
        - ipBlock:
            cidr: 150.70.149.0/27
        - ipBlock:
            cidr: 150.70.149.32/27
        - ipBlock:
            cidr: 150.70.236.0/24
        - ipBlock:
            cidr: 150.70.239.0/24
        - ipBlock:
            cidr: 216.99.131.0/24
        - ipBlock:
            cidr: 216.104.4.0/24
        - ipBlock:
            cidr: 216.104.20.0/24
      ports:
        - protocol: TCP
          port: 25
  egress:
    # Allow outbound to any destination (for MX delivery)
    - to:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 25
        - protocol: TCP
          port: 587
        - protocol: TCP
          port: 465
    # Allow DNS for MX lookups
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
```

---

## 8. Rate Limiting under CEGP Load

### 8.1 Expected Load Profile

When CEGP scans and relays messages:

- **Inbound Rate to Relay:** Variable, depends on customer email volume
- **CEGP Rate Limits (per spec):** 
  - Inbound: 2,000 msg/min per IP
  - Recipient: 200 msg/min per email
- **Relay Rate Limits:** Match or exceed CEGP limits

### 8.2 Rate Limit Configuration

```yaml
# Kubernetes Deployment
env:
  - name: RATE_LIMIT_IP_PER_MIN
    value: "2500"      # Slightly higher than CEGP (2000)
  - name: RATE_LIMIT_RCPT_PER_MIN
    value: "250"       # Slightly higher than CEGP (200)
```

**Why slightly higher?** To avoid cascading rejections if CEGP legitimately spikes.

### 8.3 Auto-Scaling for CEGP Throughput

The HPA automatically scales the relay based on CPU/memory:

```yaml
minReplicas: 3      # Always have 3 relays
maxReplicas: 50     # Can scale to 50 during viral campaigns
```

With 3 pods, max sustained throughput:
- Per-pod: ~670 msg/min (2000 / 3)
- Total cluster: 2000+ msg/min

---

## 9. Monitoring & Observability

### 9.1 Key Metrics for CEGP Integration

```
relay_messages_received_total
  - Label: domain (e.g., "company.com")
  - Label: src_ip (should be CEGP's IP)
  - Use: Track volume from CEGP

relay_messages_delivered_total
  - Label: status ("success", "deferred", "bounced")
  - Use: Confirm delivery to destination

relay_rate_limit_hits_total
  - Label: type ("ip", "rcpt")
  - Use: Alert if CEGP is rate-limited (queue buildup)

relay_queue_size_messages
  - Use: Monitor if messages are backing up (CEGP outpacing delivery)

relay_delivery_latency_seconds
  - Use: Track end-to-end delivery time
```

### 9.2 Alerting Rules

```yaml
# Alert if queue is growing (destination unreachable)
- alert: CegpRelayQueueBacklog
  expr: relay_queue_size_messages > 10000
  for: 5m
  annotations:
    summary: "CEGP relay queue is backing up"

# Alert if rate-limited by own limits
- alert: CegpRelayRateLimited
  expr: rate(relay_rate_limit_hits_total[5m]) > 10
  for: 1m
  annotations:
    summary: "Relay is rate-limiting (may need scale-up)"

# Alert if CEGP connection is from unexpected IP
- alert: UnauthorizedSmtpConnection
  expr: relay_connection_total{status="rejected"} > 0
  annotations:
    summary: "Unauthorized SMTP connection to relay"
```

### 9.3 Logging Strategy

All messages logged as JSON for easy parsing:

```json
{
  "timestamp": "2025-03-25T14:32:15.123Z",
  "event": "message_relayed",
  "src_ip": "150.70.149.5",
  "from": "user@company.com",
  "rcpt": "recipient@gmail.com",
  "message_id": "<abc123@company.com>",
  "size_bytes": 25000,
  "cegp_processing_time_ms": 1250,
  "destination_mta": "gmail.com",
  "delivery_status": "success",
  "relay_processing_time_ms": 3500,
  "total_time_ms": 4750
}
```

---

## 10. Testing the Integration

### 10.1 Pre-Deployment Checklist

- [ ] Relay container image built and pushed to registry
- [ ] Kubernetes manifests reviewed and customized
- [ ] CEGP domain added in console with "User-Defined Mail Servers"
- [ ] CEGP outbound server IP/FQDN configured (points to relay)
- [ ] Relay permit-ips.conf contains CEGP's IP ranges
- [ ] Relay domains.conf contains test domain
- [ ] DNS name resolution verified (relay.email-security.svc.cluster.local)
- [ ] LoadBalancer IP assigned and routable from CEGP

### 10.2 Step 1: Deploy Relay Container

```bash
kubectl apply -f kubernetes-deployment.yaml
kubectl wait --for=condition=ready pod -l app=cegp-smtp-relay -n email-security
```

### 10.3 Step 2: Verify Connectivity from CEGP

In CEGP Console → Domains → [Your Domain] → Outbound Servers:

Click **"Send Test Message"**
- CEGP sends a test message to your relay
- Message is relayed to the test email address
- Confirm message arrives

**Troubleshooting:**
```bash
# Check pod logs for connection from CEGP
kubectl logs -f deployment/cegp-smtp-relay -n email-security | grep "150.70"

# Check metrics
kubectl port-forward svc/cegp-smtp-relay 9090:9090 &
curl http://localhost:9090/metrics | grep relay_connection_total
```

### 10.4 Step 3: Send Production Test

1. Create a test email account in your domain
2. Send email through your normal mail system (not CEGP yet)
3. Verify it arrives unscanned
4. Now enable CEGP scanning and repeat
5. Verify scanned message arrives

---

## 11. Troubleshooting Guide

### Symptom: "Connection refused" from CEGP

**Cause:** Relay container not accepting connections from CEGP IP

**Fix:**
```bash
# Check permit list includes CEGP IP
kubectl get configmap relay-policy -n email-security \
  -o jsonpath='{.data.permit-ips\.conf}'

# Add CEGP IP range if missing
kubectl patch configmap relay-policy -n email-security \
  --type merge -p '{"data":{"permit-ips.conf":"150.70.149.0/27\n150.70.149.32/27"}}'
```

### Symptom: Messages rejected "550 Relay access denied"

**Cause:** Domain not in relay_domains.conf

**Fix:**
```bash
# Update domains.conf
kubectl patch configmap relay-policy -n email-security \
  --type merge -p '{"data":{"domains.conf":"company.com"}}'
```

### Symptom: "452 Service temporarily unavailable"

**Cause:** Rate limit exceeded or queue backed up

**Fix:**
```bash
# Check queue size
kubectl port-forward svc/cegp-smtp-relay 9090:9090 &
curl http://localhost:9090/metrics | grep relay_queue_size

# Check if destination is reachable
kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- \
  nc -zv mx.google.com 25

# Scale up if needed
kubectl scale deployment cegp-smtp-relay --replicas=10 -n email-security
```

---

## 12. References

- **CEGP Documentation:** https://docs.trendmicro.com/en-us/documentation/article/trend-vision-one-adding-domain
- **Rate Limits:** https://success.trendmicro.com/en-US/solution/KA-0020120
- **Postfix Manual:** http://www.postfix.org/
- **RFC 5321 (SMTP):** https://tools.ietf.org/html/rfc5321

---

**Document Version:** 2.0 (CEGP User-Defined Mail Servers)  
**Last Updated:** March 2025  
**Status:** Production Ready
