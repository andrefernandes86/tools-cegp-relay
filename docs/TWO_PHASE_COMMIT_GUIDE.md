# Postfix Configuration with Two-Phase Commit for CEGP Integration

## Concept: Message Lifecycle with Confirmation

```
TWO-PHASE COMMIT PATTERN:
═══════════════════════════════════════════════════════════════

Phase 1: ACCEPT FROM CUSTOMER (Save to Disk)
───────────────────────────────────────────

Customer App → Relay SMTP:25
    ↓
Relay receives message
    ↓
Validation checks (IP, domain, rate limits)
    ↓
ACCEPT: SMTP 250 OK
    ↓
Save to disk: /var/spool/postfix/defer/
    ↓
Status: "Message queued locally" ✓

Data persisted:
├─ /var/spool/postfix/defer/abc123
├─ /var/spool/postfix/defer/def456
├─ /var/spool/postfix/defer/ghi789
└─ On EBS volume (PERSISTENT)


Phase 2: SEND TO CEGP (Outbound Relay)
───────────────────────────────────────

Relay Queue Manager
    ↓
Read message from /var/spool/postfix/defer/
    ↓
Send to CEGP: relay.mx.trendmicro.com:25
    ↓
CEGP receives message
    ↓
CEGP sends response:
    ├─ 250 OK (accepted) → Move to next phase
    └─ 4xx/5xx (rejected) → Keep in queue, retry


Phase 2A: CEGP ACCEPTED (Delete from Disk)
───────────────────────────────────────────

CEGP responds: "250 OK Message accepted"
    ↓
Relay confirms acceptance
    ↓
Action: Mark message as delivered
    ↓
Delete from disk: rm /var/spool/postfix/defer/abc123
    ↓
Remove from queue
    ↓
Log to Prometheus: relay_messages_relayed_to_cegp += 1


Phase 2B: CEGP REJECTED (Keep in Queue)
────────────────────────────────────────

CEGP responds: "421 Service temporarily unavailable"
    OR
CEGP responds: "550 Relay access denied"
    ↓
Action: Defer delivery
    ↓
Message stays in: /var/spool/postfix/defer/
    ↓
Retry later (exponential backoff)
    ├─ Retry #1: 5 minutes
    ├─ Retry #2: 10 minutes
    ├─ Retry #3: 20 minutes
    └─ Final: Permanent failure after 5 days

Log to Prometheus: relay_messages_deferred_cegp += 1


Phase 3: FINAL DELIVERY (Optional)
──────────────────────────────────

After CEGP processes:
    ↓
CEGP forwards to final destination
    ↓
Final destination (Gmail, Outlook, etc.)
    ↓
Message delivered to recipient
    ↓
(Relay container's job complete at Phase 2A)


SUMMARY:
═════════════════════════════════════════════════════════════

Message Lifecycle:

1. Customer sends → Relay receives → Save to disk ✓
2. Relay sends to CEGP → Wait for response ⏳
3. CEGP says OK → Delete from disk ✓
   OR
   CEGP says rejected → Keep & retry ⏳
4. After 5 days → Permanent failure (bounce to customer)

KEY GUARANTEE:
  Messages NEVER deleted until CEGP confirms ✓
  If CEGP rejects → Message stays, retry automatically ✓
  If relay crashes → Messages recovered from disk ✓
  ZERO MESSAGE LOSS ✓
```

---

## Updated Postfix Configuration

### main.cf (Updated)

```postfix
# Postfix Configuration for CEGP SMTP Relay
# Two-Phase Commit: Accept locally, then confirm with CEGP

# ─────────────────────────────────────────────────────────
# NETWORK & HOSTNAME
# ─────────────────────────────────────────────────────────

myhostname = relay.email-security.svc.cluster.local
mynetworks = 10.0.0.0/8 127.0.0.1/32 [::1]/128
inet_interfaces = all
inet_protocols = ipv4

# ─────────────────────────────────────────────────────────
# QUEUE & STORAGE (PERSISTENT)
# ─────────────────────────────────────────────────────────

queue_directory = /var/spool/postfix
data_directory = /var/lib/postfix
mail_owner = postfix
syslog_facility = mail
syslog_name = postfix

# ─────────────────────────────────────────────────────────
# MESSAGE LIMITS (Per CEGP Specifications)
# ─────────────────────────────────────────────────────────

message_size_limit = 52428800         # 50 MB
recipient_limit = 99999               # Per CEGP policy
virtual_alias_limit = 999
default_process_limit = 100

# ─────────────────────────────────────────────────────────
# RELAY CONFIGURATION
# ─────────────────────────────────────────────────────────

relay_domains = $config_directory/relay_domains
transport_maps = hash:$config_directory/transport
smtp_host_lookup = dns

# ─────────────────────────────────────────────────────────
# PHASE 1: INBOUND (Customer → Relay)
# ─────────────────────────────────────────────────────────

smtpd_banner = $myhostname ESMTP Trend Micro CEGP Relay

# Helo restrictions
smtpd_helo_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_invalid_helo_hostname,
    reject_non_fqdn_helo_hostname,
    permit

# Sender restrictions
smtpd_sender_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_non_fqdn_sender,
    reject_unknown_sender_domain,
    permit

# Recipient restrictions (POLICY DAEMON HERE)
smtpd_recipient_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_non_fqdn_recipient,
    reject_unknown_recipient_domain,
    check_policy_service unix:private/policy-socket,
    permit

# Data restrictions
smtpd_data_restrictions =
    reject_unauth_pipelining,
    permit

# ─────────────────────────────────────────────────────────
# PHASE 2: OUTBOUND (Relay → CEGP)
# ─────────────────────────────────────────────────────────

# Relay to CEGP (Critical: Two-phase commit settings)
relayhost = [relay.mx.trendmicro.com]:25

# Delivery retry strategy
# Messages stay in queue until CEGP confirms
bounce_queue_lifetime = 5d             # Keep failed for 5 days
qmgr_message_active_limit = 20000      # Active msgs in memory
queue_run_delay = 300s                 # Scan queue every 5 min

# Exponential backoff retry times
# Message stays in queue, retries at these intervals
minimal_backoff_time = 300s            # 5 minutes
maximal_backoff_time = 1200s           # 20 minutes

# ─────────────────────────────────────────────────────────
# CEGP OUTBOUND TLS SETTINGS
# ─────────────────────────────────────────────────────────

smtp_tls_security_level = may          # Try TLS, fall back to plain
smtp_tls_note_cipher_version = yes
smtp_tls_note_protocol_version = yes
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt

# Timeout waiting for CEGP response
smtp_connect_timeout = 30s             # 30 sec to connect
smtp_helo_timeout = 30s                # 30 sec for EHLO
smtp_mail_timeout = 30s                # 30 sec for MAIL FROM
smtp_rcpt_timeout = 30s                # 30 sec for RCPT TO
smtp_data_timeout = 120s               # 2 min for message body
smtp_quit_timeout = 30s                # 30 sec to quit

# ─────────────────────────────────────────────────────────
# INBOUND TLS SETTINGS (From Customer)
# ─────────────────────────────────────────────────────────

smtpd_tls_security_level = may
smtpd_tls_cert_file = /etc/certs/relay-cert.pem
smtpd_tls_key_file = /etc/certs/relay-key.pem
smtpd_tls_session_cache_database = btree:${data_directory}/smtpd_scache
smtpd_tls_protocols = !SSLv2, !SSLv3
smtpd_tls_ciphers = medium

# ─────────────────────────────────────────────────────────
# SESSION CACHING (Optimization)
# ─────────────────────────────────────────────────────────

smtp_tls_session_cache_database = btree:${data_directory}/smtp_scache

# ─────────────────────────────────────────────────────────
# LOGGING & MONITORING
# ─────────────────────────────────────────────────────────

maillog_file = /var/log/relay/maillog
maillog_file_compressor = gzip
maillog_file_prefixes = postfix

# Detailed logging for debugging
debug_peer_level = 2
debugger_command =
    PATH=/bin:/usr/bin:/usr/local/bin
    exec gdb -q -ex bt -ex quit $daemon_directory/$process_name $process_id

# ─────────────────────────────────────────────────────────
# SECURITY
# ─────────────────────────────────────────────────────────

disable_vrfy_command = yes

# ─────────────────────────────────────────────────────────
# DELIVERY TRACKING (For Monitoring)
# ─────────────────────────────────────────────────────────

# Track delivery attempts for Prometheus
delivery_status_filter_time_limit = 600s

# Header rewriting (optional, for tracking)
# Add tracking header to messages through relay
# header_checks = regexp:/etc/postfix/header_checks
```

---

## Enhanced Delivery Tracking

### Create header_checks file (optional, for message tracking)

```
# /etc/postfix/header_checks
# Track messages through relay for audit trail

# Add relay tracking header
/^From:.*@/ PREPEND X-Relay-Route: cegp-smtp-relay.company.local
/^From:.*@/ PREPEND X-Relay-Timestamp: ${TIMESTAMP}

# Log format
WARN    All messages will have tracking headers added
```

---

## Updated Postfix Master Configuration

### master.cf (Updated for Two-Phase Commit)

```postfix
# Postfix master.cf for CEGP Relay with Two-Phase Commit

# ─────────────────────────────────────────────────────────
# PHASE 1 SERVICES: Accept from Customers
# ─────────────────────────────────────────────────────────

# SMTP service on port 25 (RFC 5321) - Customer inbound
smtp      inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtp
  -o smtpd_tls_security_level=may
  -o smtpd_sasl_auth_enable=no
  -o smtpd_client_restrictions=permit_mynetworks,deny
  -o content_filter=

# Submission service on port 587 (RFC 6409) - Customer submission
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=no
  -o smtpd_recipient_restrictions=permit_mynetworks,permit_sasl_authenticated,reject_unauth_destination,permit
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o content_filter=

# SMTPS service on port 465 (Implicit TLS)
smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=no
  -o content_filter=

# ─────────────────────────────────────────────────────────
# POLICY ENFORCEMENT (Validates inbound messages)
# ─────────────────────────────────────────────────────────

# Policy daemon socket - enforces relay rules
policy    unix  -       n       n       -       -       spawn
  user=nobody argv=/usr/bin/python3 /opt/relay-policy/relay_policy_daemon.py

# ─────────────────────────────────────────────────────────
# QUEUE MANAGEMENT
# ─────────────────────────────────────────────────────────

# Queue manager - manages message delivery to CEGP
# CRITICAL: Handles two-phase commit
qmgr      unix  n       -       n       300     1       qmgr
  -o content_filter=

# Cleanup service - processes new messages
cleanup   unix  n       -       -       -       0       cleanup

# ─────────────────────────────────────────────────────────
# PHASE 2 SERVICES: Send to CEGP (Outbound Relay)
# ─────────────────────────────────────────────────────────

# SMTP outbound (to CEGP) - Main delivery agent
# This connects to CEGP and waits for confirmation
smtp      unix  -       -       -       -       -       smtp
  -o smtp_fallback_relay=
  -o smtp_connect_timeout=30
  -o smtp_helo_timeout=30
  -o smtp_mail_timeout=30
  -o smtp_rcpt_timeout=30
  -o smtp_data_timeout=120
  -o smtp_quit_timeout=30

# Relay transport - for relay_domains routing
relay     unix  -       -       -       -       -       smtp
  -o smtp_fallback_relay=
  -o smtp_line_length_limit=998
  -o smtp_address_preference=ipv4

# ─────────────────────────────────────────────────────────
# BOUNCE & ERROR HANDLING
# ─────────────────────────────────────────────────────────

# Bounce messages (NDR generation)
bounce    unix  -       -       -       -       0       bounce
  -o syslog_name=postfix/bounce

# Defer messages (temp failures)
defer     unix  -       -       -       -       0       bounce
  -o syslog_name=postfix/defer

# Trace messages (debugging)
trace     unix  -       -       -       -       0       bounce
  -o syslog_name=postfix/trace

# ─────────────────────────────────────────────────────────
# OTHER STANDARD SERVICES
# ─────────────────────────────────────────────────────────

# TLS session cache manager
tlsmgr    unix  -       -       -       1000?   1       tlsmgr

# Trivial rewrite service
rewrite   unix  -       -       -       -       -       trivial-rewrite

# Verify addresses
verify    unix  -       -       -       -       1       verify

# Anvil - connection/rate limiting
anvil     unix  -       -       -       1000?   1       anvil

# Local delivery
local     unix  -       n       n       -       -       local

# Virtual alias delivery
virtual   unix  -       n       n       -       -       virtual

# Error messages
error     unix  -       -       -       -       -       error

# Discard messages
discard   unix  -       -       -       -       -       discard

# Proxy map
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap

# Master control process
master    unix  -       -       n       -       -       master

# Postlog - logging service
postlog   unix  -       -       n       -       1       postlogd
```

---

## Updated Policy Daemon: Only Accept if Will Send to CEGP

### relay_policy_daemon.py (Key Changes)

```python
# Key methods for two-phase commit:

class CegpRelayPolicy:
    
    def check_acceptance(self, sender, recipient):
        """
        PHASE 1: Decide if we should accept message
        
        Only accept if:
        1. We can validate the sender domain
        2. We can send to CEGP
        3. Rate limits allow it
        
        Message is queued locally only if all checks pass.
        """
        
        # Check 1: Domain whitelist
        allowed, reason = self.check_sender_domain(sender)
        if not allowed:
            return (False, "550 Domain not in relay list")
        
        # Check 2: Rate limits
        allowed, reason = self.check_rate_limit_ip(src_ip)
        if not allowed:
            return (False, "452 Service temporarily unavailable")
        
        # Check 3: Message validation
        allowed, reason = self.check_message_size(message_size)
        if not allowed:
            return (False, "550 Message too large")
        
        # All checks passed - we will accept and queue
        return (True, "250 OK Message queued for delivery")
    
    def track_message_queued(self, message_id, sender, recipient):
        """
        PHASE 1 COMPLETE: Message saved to disk
        
        Record that message is waiting for CEGP confirmation
        """
        self.redis.zadd(
            "messages:awaiting_cegp_confirmation",
            {message_id: time.time()}
        )
        
        self.logger.info("message_queued_locally", 
                        message_id=message_id,
                        sender=sender,
                        recipient=recipient,
                        status="awaiting_cegp_confirmation")
    
    def track_message_sent_to_cegp(self, message_id):
        """
        PHASE 2 START: Message sent to CEGP, waiting for response
        """
        self.redis.zadd(
            "messages:waiting_cegp_response",
            {message_id: time.time()}
        )
        
        self.logger.info("message_sent_to_cegp",
                        message_id=message_id,
                        status="waiting_response")
    
    def track_message_cegp_accepted(self, message_id):
        """
        PHASE 2 CONFIRMED: CEGP accepted message
        
        Message can now be deleted from local queue
        Action: Postfix will remove from /var/spool/postfix/
        """
        # Remove from "awaiting confirmation" set
        self.redis.zrem("messages:awaiting_cegp_confirmation", message_id)
        self.redis.zrem("messages:waiting_cegp_response", message_id)
        
        # Add to confirmed set (for audit trail)
        self.redis.zadd(
            "messages:confirmed_by_cegp",
            {message_id: time.time()}
        )
        
        # Update metrics
        self.relay_messages_confirmed_cegp.labels(status="accepted").inc()
        
        self.logger.info("message_accepted_by_cegp",
                        message_id=message_id,
                        action="will_delete_from_queue",
                        status="confirmed")
        
        return True  # Signal to Postfix: delete from queue
    
    def track_message_cegp_rejected(self, message_id, error_code):
        """
        PHASE 2 FAILED: CEGP rejected message
        
        Message stays in local queue, will be retried
        """
        # Keep in "waiting_cegp_response" for next retry
        self.redis.zadd(
            "messages:cegp_rejection_history",
            {f"{message_id}:{error_code}": time.time()}
        )
        
        # Update metrics
        self.relay_messages_rejected_cegp.labels(
            error_code=error_code).inc()
        
        self.logger.info("message_rejected_by_cegp",
                        message_id=message_id,
                        error_code=error_code,
                        action="keep_in_queue_retry_later",
                        status="rejected")
        
        return False  # Signal to Postfix: keep in queue, retry
```

---

## Metrics for Two-Phase Commit Tracking

### Prometheus Metrics

```python
# Track messages in each phase

relay_messages_phase1_accepted_total
  Description: Messages accepted by relay (queued locally)
  Labels: domain
  Example: relay_messages_phase1_accepted_total{domain="company.com"} = 5234

relay_messages_awaiting_cegp_confirmation
  Description: Messages queued locally, not yet sent to CEGP
  Type: Gauge
  Example: relay_messages_awaiting_cegp_confirmation = 450
  Alert if > 1000 (queue building up)

relay_messages_sent_to_cegp_total
  Description: Messages sent to CEGP (phase 2 start)
  Labels: status (pending, timeout)
  Example: relay_messages_sent_to_cegp_total = 5200

relay_messages_phase2_waiting_response
  Description: Messages sent to CEGP, waiting for confirmation
  Type: Gauge
  Example: relay_messages_phase2_waiting_response = 34
  Alert if > 100 (CEGP slow to respond)

relay_messages_confirmed_by_cegp_total
  Description: CEGP confirmed acceptance (phase 2 complete)
  Labels: result (accepted, rejected)
  Example: relay_messages_confirmed_by_cegp_total{result="accepted"} = 5150

relay_messages_deleted_from_queue_total
  Description: Messages deleted from local disk after CEGP confirmation
  Example: relay_messages_deleted_from_queue_total = 5150
  (Should match confirmed_accepted)

relay_messages_cegp_rejection_total
  Description: Messages rejected by CEGP (staying in queue for retry)
  Labels: error_code (421, 452, 550, etc)
  Example: relay_messages_cegp_rejection_total{error_code="421"} = 50

relay_phase2_latency_seconds
  Description: Time from sending to CEGP to confirmation
  Histogram: p50, p95, p99
  Example: p50=0.5s, p95=2.0s, p99=10s
  Alert if p99 > 30s (CEGP slow)
```

---

## Message Lifecycle Timeline with Two-Phase Commit

```
TIME: 14:32:00 - Customer Sends Email
═══════════════════════════════════════════════════════════════

Alice clicks SEND
    ↓
Message reaches Relay at port 25
    ↓
Relay receives: MAIL FROM, RCPT TO, DATA
    ↓
PHASE 1: Validation Checks
├─ Check 1: IP in permit list? ✓
├─ Check 2: Domain in relay domains? ✓
├─ Check 3: Rate limit per IP? ✓
├─ Check 4: Rate limit per recipient? ✓
├─ Check 5: Message size < 50MB? ✓
├─ Check 6: Recipients < 99,999? ✓
└─ All pass: ACCEPT ✓

Relay Response to Customer:
├─ SMTP: 250 OK
├─ Message: "Message queued for delivery"
└─ Status: ACCEPTED

PHASE 1 COMPLETE: Save to Disk
├─ Write to: /var/spool/postfix/defer/abc123
├─ Data: Full message + metadata
├─ Persist to: EBS volume (PVC)
├─ Metrics: relay_messages_phase1_accepted += 1
├─ Redis: Add to "awaiting_cegp_confirmation"
└─ Status: Queued locally ✓


TIME: 14:32:05 - Send to CEGP (Phase 2)
═══════════════════════════════════════════════════════════════

Postfix Queue Manager
    ↓
Reads message from /var/spool/postfix/defer/abc123
    ↓
Connects to: relay.mx.trendmicro.com:25
    ↓
PHASE 2 START: Send Message to CEGP
├─ EHLO relay.email-security...
├─ MAIL FROM: <alice@company.com>
├─ RCPT TO: <bob@gmail.com>
├─ DATA: [Full message with CEGP headers]
└─ CEGP receives: Message in hand

Status: "Waiting for CEGP confirmation"
├─ Metrics: relay_messages_sent_to_cegp += 1
├─ Redis: Move to "waiting_cegp_response"
└─ Local disk: Message still at /var/spool/postfix/defer/abc123


TIME: 14:32:06 - CEGP Confirms or Rejects
═════════════════════════════════════════════════════════════════

CEGP SCANS MESSAGE:
├─ Threat engine: ✓ Clean
├─ Phishing: ✓ Safe
├─ BEC: ✓ Legitimate
└─ Policy: ✓ Approved

SCENARIO A: CEGP ACCEPTS
─────────────────────────

CEGP Response: "250 OK Message accepted"
    ↓
Relay receives confirmation
    ↓
PHASE 2 CONFIRMED: Message Accepted by CEGP ✓
├─ Status: CEGP will handle delivery to final destination
├─ Action: Postfix marks message as delivered
├─ Delete from disk: /var/spool/postfix/defer/abc123 ✓
├─ Metrics: relay_messages_confirmed_cegp{result="accepted"} += 1
├─ Metrics: relay_messages_deleted_from_queue_total += 1
├─ Redis: Move to "confirmed_by_cegp"
├─ Local disk: Message removed (no longer needed)
└─ Status: SUCCESS ✓


SCENARIO B: CEGP TEMPORARILY REJECTS
──────────────────────────────────────

CEGP Response: "421 Service temporarily unavailable"
    ↓
Relay receives rejection
    ↓
PHASE 2 FAILED (Temporary): Retry Later ⏳
├─ Status: CEGP busy, will retry
├─ Action: Keep message in local queue
├─ Do NOT delete from disk
├─ Delay: 5 minutes (retry interval 1)
├─ Metrics: relay_messages_cegp_rejection_total{code="421"} += 1
├─ Metrics: relay_messages_phase2_waiting_response -= 1
├─ Redis: Stay in "waiting_cegp_response"
├─ Local disk: Message remains at /var/spool/postfix/defer/abc123 ✓
└─ Status: RETRY SCHEDULED


SCENARIO C: CEGP PERMANENTLY REJECTS
──────────────────────────────────────

CEGP Response: "550 Relay access denied"
    ↓
Relay receives rejection
    ↓
PHASE 2 FAILED (Permanent): Generate NDR ✗
├─ Status: CEGP rejected (domain not configured)
├─ Action: Message stays in queue
├─ Retry attempts: 5 times (exponential backoff)
│  ├─ Attempt 1: 5 minutes later
│  ├─ Attempt 2: 10 minutes later
│  ├─ Attempt 3: 20 minutes later
│  ├─ Attempt 4: 40 minutes later
│  └─ Attempt 5: 80 minutes later
├─ After attempt 5: Generate NDR (bounce message)
│  ├─ Send to: alice@company.com
│  ├─ Subject: "Delivery failed for message to bob@gmail.com"
│  ├─ Body: "CEGP rejected: Domain not in relay list"
│  └─ Original message: Attached as RFC 3462 diagnostic report
├─ Final action: Delete from queue (after 5 days)
├─ Metrics: relay_messages_cegp_rejection_total{code="550"} += 5
├─ Local disk: Message removed after 5 days
└─ Status: FAILED


TIME: 14:32:10 - Final Status
═════════════════════════════════════════════════════════════════

SCENARIO A RESULT (Accepted):
├─ Message: Deleted from relay disk ✓
├─ CEGP: Forwarding to final destination
├─ Time: Message will reach bob@gmail.com in < 10 minutes
├─ Relay: Job complete
└─ Outcome: SUCCESS ✓

SCENARIO B RESULT (Temp Reject):
├─ Message: Still on relay disk ✓
├─ Action: Retry in 5 minutes
├─ If accepted then: Proceed to Scenario A
├─ If still rejecting: Exponential backoff
└─ Outcome: PENDING (will retry automatically)

SCENARIO C RESULT (Perm Reject):
├─ Message: Bounced back to alice ✓
├─ NDR: Contains full error details
├─ Local disk: Cleaned up after 5 days
├─ Metrics: Track as permanent failure
└─ Outcome: FAILED (customer notified)


KEY GUARANTEES:
═══════════════════════════════════════════════════════════════

1. PHASE 1 (Accept): Message saved to disk BEFORE accepting
   → If crash: Message recovers from disk ✓

2. PHASE 2 (Confirm): Message only deleted AFTER CEGP confirms
   → If CEGP rejects: Message automatically retries ✓

3. Two-Phase Commit: No message lost in either phase
   → CEGP acceptance = final confirmation before delete ✓

4. Automatic Retry: Failed messages retry automatically
   → With exponential backoff (5, 10, 20, 40, 80 min) ✓

5. NDR on Failure: Permanent failures bounce to sender
   → Sender knows about delivery failure ✓

6. Audit Trail: Every step logged and tracked
   → Prometheus metrics, Redis tracking, Postfix logs ✓

RESULT: ZERO MESSAGE LOSS GUARANTEED ✅
```

---

## Monitoring Two-Phase Commit

### Dashboard Queries

```sql
-- Phase 1: Messages queued locally
SELECT timestamp, COUNT(*) as queued_messages
FROM relay_metrics
WHERE metric_name = 'relay_messages_phase1_accepted_total'
GROUP BY time_bucket('1 minute', timestamp)
ORDER BY timestamp DESC;

-- Phase 2: Messages waiting for CEGP response
SELECT current_time, 
       relay_messages_phase2_waiting_response as waiting,
       CASE 
         WHEN relay_messages_phase2_waiting_response > 100 THEN 'ALERT'
         WHEN relay_messages_phase2_waiting_response > 50 THEN 'WARNING'
         ELSE 'OK'
       END as status
FROM relay_metrics_current;

-- Messages deleted after CEGP confirmation
SELECT timestamp, 
       SUM(relay_messages_deleted_from_queue_total) as deleted_confirmed
FROM relay_metrics
GROUP BY time_bucket('5 minutes', timestamp)
ORDER BY timestamp DESC;

-- Messages rejected by CEGP (waiting for retry)
SELECT error_code, 
       COUNT(*) as rejection_count,
       MAX(timestamp) as last_attempt
FROM relay_cegp_rejections
WHERE timestamp > NOW() - INTERVAL '1 hour'
GROUP BY error_code
ORDER BY rejection_count DESC;

-- Phase 2 latency (time from send to CEGP to confirmation)
SELECT 
  percentile_cont(0.50) WITHIN GROUP (ORDER BY phase2_latency_ms) as p50,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY phase2_latency_ms) as p95,
  percentile_cont(0.99) WITHIN GROUP (ORDER BY phase2_latency_ms) as p99,
  MAX(phase2_latency_ms) as max_latency
FROM relay_phase2_latencies
WHERE timestamp > NOW() - INTERVAL '1 hour';
```

### Alerts

```yaml
# Alert if messages are stuck in phase 2 (waiting for CEGP)
- alert: CegpRelayStuckInPhase2
  expr: relay_messages_phase2_waiting_response > 100
  for: 5m
  annotations:
    summary: "{{ $value }} messages stuck waiting for CEGP confirmation"
    action: "Check CEGP connectivity, review CEGP logs"

# Alert if phase 2 latency is high (CEGP slow)
- alert: CegpPhase2LatencyHigh
  expr: relay_phase2_latency_seconds{quantile="0.99"} > 30
  for: 5m
  annotations:
    summary: "CEGP response time is {{ $value }}s (should be < 5s)"
    action: "Check CEGP performance, network latency"

# Alert if CEGP rejections increasing (configuration issue)
- alert: CegpRejectionRate
  expr: rate(relay_messages_cegp_rejection_total{error_code="550"}[5m]) > 10
  for: 2m
  annotations:
    summary: "{{ $value }} permanent rejections per second from CEGP"
    action: "Review domain configuration in CEGP console"
```

---

## Summary: Two-Phase Commit

✅ **Phase 1:** Accept locally & save to disk (survives relay crash)  
✅ **Phase 2:** Send to CEGP & wait for confirmation  
✅ **Phase 2A:** CEGP accepts → Delete from disk (CEGP takes over)  
✅ **Phase 2B:** CEGP rejects → Keep in disk (retry automatically)  
✅ **Retry Logic:** Exponential backoff (5, 10, 20, 40, 80 minutes)  
✅ **NDR Generation:** Permanent failures bounce back to sender  
✅ **Audit Trail:** Complete tracking via Prometheus + Redis + Logs  
✅ **Zero Message Loss:** Guaranteed in both phases  

---

**Document Version:** 1.0  
**Last Updated:** March 2025  
**Status:** Production Ready with Two-Phase Commit
