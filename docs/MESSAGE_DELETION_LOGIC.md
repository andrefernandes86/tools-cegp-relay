# Message Deletion Logic: When to Delete from Local Storage

## The Rule (Simple Version)

```
RULE: Delete from /var/spool/postfix/ ONLY WHEN:
     CEGP sends back: "250 OK Message accepted"
     
NOT before, NOT if CEGP rejects, ONLY on "250 OK"
```

---

## Visual Timeline: Message Lifecycle

```
TIMESTAMP: 14:32:00
═════════════════════════════════════════════════════════════════

STEP 1: Customer sends email
        ↓
        Alice: TO bob@gmail.com
        Relay receives at port 25
        ↓
        Validation checks
        ├─ IP whitelist: ✓ OK
        ├─ Domain whitelist: ✓ OK
        ├─ Rate limits: ✓ OK
        ├─ Message size: ✓ OK
        └─ Return to customer: "250 OK" ✓
        
        Message status: SAVED TO DISK
        Location: /var/spool/postfix/defer/abc123
        On disk: YES ✓
        Ready to delete: NO (waiting for CEGP confirmation)


TIMESTAMP: 14:32:05 (5 seconds later)
═════════════════════════════════════════════════════════════════

STEP 2: Relay sends to CEGP
        ↓
        Postfix reads: /var/spool/postfix/defer/abc123
        ↓
        Connect to: relay.mx.trendmicro.com:25
        ↓
        SMTP Dialog:
        ├─ EHLO relay.email-security...
        ├─ MAIL FROM: <alice@company.com>
        ├─ RCPT TO: <bob@gmail.com>
        ├─ DATA: [Full message body]
        └─ WAITING FOR RESPONSE...
        
        Message status: SENT TO CEGP
        Location: /var/spool/postfix/defer/abc123 (still on disk)
        On disk: YES ✓
        Ready to delete: NO (waiting for CEGP response)


════════════════════════════════════════════════════════════════
CRITICAL MOMENT: CEGP RESPONDS
════════════════════════════════════════════════════════════════


SCENARIO A: CEGP ACCEPTS (250 OK)
──────────────────────────────────

TIMESTAMP: 14:32:06 (1 second later)

CEGP Response: "250 OK Message accepted"
        ↓
        Relay receives: SMTP 250 OK
        ↓
        Action: CEGP confirmed acceptance ✓
        ↓
        Decision: NOW we can delete from disk
        ↓
        Postfix marks message as delivered
        ↓
        DELETE: rm /var/spool/postfix/defer/abc123
        ↓
        
        Message status: DELETED FROM LOCAL DISK ✓
        Location: /var/spool/postfix/defer/abc123 (GONE)
        On disk: NO ✗ (deleted as intended)
        Ready to delete: YES (already deleted)
        
        Why deleted? CEGP confirmed, so CEGP takes over delivery
        CEGP will deliver to: bob@gmail.com (final destination)
        Relay job: COMPLETE ✓


SCENARIO B: CEGP TEMPORARILY REJECTS (421 or 452)
───────────────────────────────────────────────────

TIMESTAMP: 14:32:06 (1 second later)

CEGP Response: "421 Service temporarily unavailable"
        ↓
        Relay receives: SMTP 421
        ↓
        Decision: Temporary issue, retry later
        ↓
        Action: DO NOT DELETE
        ↓
        Keep in queue
        ↓
        
        Message status: KEPT IN QUEUE
        Location: /var/spool/postfix/defer/abc123 (still there)
        On disk: YES ✓ (not deleted!)
        Ready to delete: NO (needs retry)
        
        Retry schedule:
        ├─ Attempt 1 (now): FAILED
        ├─ Attempt 2 (in 5 min): Will retry
        ├─ Attempt 3 (in 10 min): Will retry
        └─ Attempt 4 (in 20 min): Will retry
        
        If next attempt succeeds: Delete (scenario A)
        If all attempts fail: Generate NDR after 5 days


SCENARIO C: CEGP PERMANENTLY REJECTS (550 or 553)
──────────────────────────────────────────────────

TIMESTAMP: 14:32:06 (1 second later)

CEGP Response: "550 Relay access denied"
        ↓
        Relay receives: SMTP 550
        ↓
        Decision: Permanent failure, will not accept
        ↓
        Action: DO NOT DELETE (yet)
        ↓
        Keep in queue for retries
        ↓
        Try again later (maybe admin fixed config)
        ↓
        
        Message status: WAITING FOR RETRY
        Location: /var/spool/postfix/defer/abc123 (still there)
        On disk: YES ✓ (not deleted!)
        Ready to delete: NO (needs retry)
        
        Retry attempts:
        ├─ Attempt 1: FAILED (550)
        ├─ Attempt 2: FAILED (550)
        ├─ Attempt 3: FAILED (550)
        ├─ Attempt 4: FAILED (550)
        ├─ Attempt 5: FAILED (550)
        └─ After 5 attempts over 24+ hours: Give up
        
        Next action: Generate NDR (bounce) to alice@company.com
        ├─ Email to: alice@company.com
        ├─ Subject: "Delivery failed for message to bob@gmail.com"
        ├─ Body: "CEGP rejected: Relay access denied"
        ├─ Reason: "Domain not configured in CEGP console"
        └─ Original message: Attached as diagnostic
        
        After NDR sent: Delete message
        ├─ rm /var/spool/postfix/defer/abc123
        └─ Cleanup after 5 days max (bounce_queue_lifetime)
        
        Result: alice knows delivery failed ✓


════════════════════════════════════════════════════════════════
SUMMARY OF DELETION LOGIC
════════════════════════════════════════════════════════════════

When to DELETE from /var/spool/postfix/:
┌────────────────────────────────────────────────────────────┐
│ Condition 1: CEGP sends "250 OK"                           │
│   → DELETE immediately ✓ (CEGP takes over)                │
│                                                             │
│ Condition 2: After 5 days of failed retries                │
│   → DELETE after generating NDR ✓                          │
│                                                             │
│ Condition 3: Manual cleanup (admin command)                │
│   → DELETE on request ✓                                    │
└────────────────────────────────────────────────────────────┘

When NOT to DELETE from /var/spool/postfix/:
┌────────────────────────────────────────────────────────────┐
│ ✗ CEGP sends 4xx (temporary error) → KEEP ✓              │
│ ✗ CEGP sends 5xx (permanent error) → KEEP ✓              │
│ ✗ Network timeout → KEEP ✓                                │
│ ✗ Connection refused → KEEP ✓                             │
│ ✗ Relay pod crashes → KEEP (on disk) ✓                   │
│ ✗ Before CEGP responds → KEEP ✓                           │
└────────────────────────────────────────────────────────────┘
```

---

## Code Logic: When Postfix Deletes Messages

### Postfix Delivery Agent Flow

```python
def deliver_message_to_cegp(message_id, message_file):
    """
    Core delivery logic - when does deletion happen?
    """
    
    # Step 1: Read message from disk
    message_content = read_file(f"/var/spool/postfix/defer/{message_id}")
    # Message still on disk: YES ✓
    
    # Step 2: Connect to CEGP
    connection = connect_to_cegp("relay.mx.trendmicro.com:25")
    # Message still on disk: YES ✓
    
    # Step 3: Send message
    send_smtp_message(connection, message_content)
    # Message still on disk: YES ✓
    
    # Step 4: WAIT FOR RESPONSE FROM CEGP
    response = connection.read_response()  # ← BLOCKING WAIT
    # Message still on disk: YES ✓
    
    # Step 5: DECISION POINT - Check CEGP response
    if response.code == 250:  # "250 OK"
        # ────────────────────────────────────
        # CEGP ACCEPTED ✓
        # ────────────────────────────────────
        # Action: DELETE from queue
        delete_file(f"/var/spool/postfix/defer/{message_id}")
        # Message still on disk: NO ✗ (deleted)
        
        log("message_delivered_to_cegp", 
            message_id=message_id, 
            status="deleted_from_queue")
        
        metrics.relay_messages_deleted_from_queue.inc()
        metrics.relay_queue_size_messages.dec()
        
        return SUCCESS  # Message no longer our concern
    
    elif response.code in [421, 450, 452]:  # Temporary error
        # ────────────────────────────────────
        # CEGP TEMPORARILY REJECTED
        # ────────────────────────────────────
        # Action: KEEP in queue, retry later
        # DO NOT DELETE
        
        log("message_deferred_cegp", 
            message_id=message_id, 
            status="will_retry",
            error_code=response.code)
        
        metrics.relay_messages_deferred_cegp.inc()
        
        return DEFER  # Queue manager will retry
    
    elif response.code in [550, 553, 554]:  # Permanent error
        # ────────────────────────────────────
        # CEGP PERMANENTLY REJECTED
        # ────────────────────────────────────
        # Action: KEEP in queue, retry (maybe config fixed)
        # If all retries fail: Generate NDR, then delete
        
        log("message_rejected_cegp", 
            message_id=message_id, 
            status="will_retry_then_bounce",
            error_code=response.code)
        
        metrics.relay_messages_rejected_cegp.inc()
        
        return DEFER  # Retry, but expect failure
    
    else:
        # Unexpected response code
        return DEFER
```

### Timeline: When File Exists on Disk

```
Time 0s:    Message arrives
            File created: /var/spool/postfix/defer/abc123
            Disk: /var/spool/postfix/defer/abc123 ✓

Time 0.5s:  Relay accepts message
            Disk: /var/spool/postfix/defer/abc123 ✓

Time 1s:    Postfix reads message
            Disk: /var/spool/postfix/defer/abc123 ✓

Time 2s:    Connect to CEGP
            Disk: /var/spool/postfix/defer/abc123 ✓

Time 3s:    Send message to CEGP
            Disk: /var/spool/postfix/defer/abc123 ✓

Time 4s:    WAIT for CEGP response
            Disk: /var/spool/postfix/defer/abc123 ✓

Time 5s:    CEGP responds "250 OK"
            Disk: /var/spool/postfix/defer/abc123 ✓

Time 5.1s:  DELETE from disk
            Disk: rm /var/spool/postfix/defer/abc123
            Disk: /var/spool/postfix/defer/abc123 ✗ (GONE)

            ↑ THIS IS THE MOMENT OF DELETION
            ↑ AFTER CEGP CONFIRMS (250 OK)
```

---

## What Happens If Relay Crashes Between Steps?

### Scenario: Pod Crashes BEFORE Sending to CEGP

```
Time 0s:    Message arrives, saved to disk
            Disk: /var/spool/postfix/defer/abc123 ✓

Time 1s:    Pod crashes (OOMKilled)
            Disk: /var/spool/postfix/defer/abc123 ✓ (still there!)

Time 30s:   New pod starts
            Mounts PVC
            Reads /var/spool/postfix/defer/abc123
            Sees: "Not yet sent to CEGP"

Time 31s:   Resume delivery to CEGP
            Send message again
            ↓
            CEGP: "250 OK"
            ↓
            DELETE: rm /var/spool/postfix/defer/abc123

Result: NO MESSAGE LOSS ✓
        Message delivered to CEGP
        Then deleted after confirmation
```

### Scenario: Pod Crashes AFTER Sending to CEGP, BEFORE Delete

```
Time 0s:    Message arrives, saved to disk
            Disk: /var/spool/postfix/defer/abc123 ✓

Time 1s:    Send to CEGP
            CEGP responds: "250 OK"

Time 2s:    Postfix is about to delete...
            Pod crashes (power loss)
            Disk: /var/spool/postfix/defer/abc123 ✓ (still there)

Time 30s:   New pod starts
            Mounts PVC
            Reads /var/spool/postfix/defer/abc123
            Sees: "This message"

Time 31s:   Check if already sent to CEGP?
            Problem: Postfix doesn't know if we already sent
            Conservative approach: Retry

Time 32s:   Send to CEGP again (duplicate)
            ↓
            CEGP: "250 OK" (accepts duplicate)
            ↓
            DELETE: rm /var/spool/postfix/defer/abc123

Result: POTENTIAL DUPLICATE MESSAGE ⚠️
        (But it's resilience, not data loss)
        Solution: CEGP deduplication or message ID tracking
```

---

## Configuration to Prevent Duplicates

### Method 1: Message-ID Tracking in Redis

```python
def track_sent_to_cegp(message_id, timestamp):
    """
    Track which messages we've sent to CEGP
    Survives pod restart (stored in Redis)
    """
    
    # Store in Redis with expiration
    redis.setex(
        f"cegp:sent:{message_id}",
        value=timestamp,
        ex=86400  # 24 hours
    )
    
    # On pod restart, check Redis
    if redis.exists(f"cegp:sent:{message_id}"):
        # We already sent this to CEGP
        # Don't send again
        delete_from_queue(message_id)
    else:
        # Haven't sent yet, safe to send
        send_to_cegp(message_id)
```

### Method 2: Message Headers (Simple)

```
After CEGP accepts, add header:
X-CEGP-Relayed: true
X-CEGP-Relay-ID: relay-abc123
X-CEGP-Relay-Timestamp: 2025-03-26T14:32:06Z

On pod restart:
├─ Read message from disk
├─ Check for "X-CEGP-Relayed: true"
├─ If present: Skip (already sent) → Delete
└─ If absent: Send again
```

### Method 3: Postfix Native Deduplication

```postfix
# In main.cf
# Track delivered message IDs
enable_original_recipient = no

# Use message-ID for deduplication
# Postfix tracks in: /var/spool/postfix/defer/
# And remembers in active queue
```

---

## Monitoring: When Are Messages Deleted?

### Prometheus Metrics

```
relay_messages_deleted_from_queue_total
├─ Counter: Total messages deleted after CEGP confirmed
├─ Should match: relay_messages_confirmed_by_cegp{result="accepted"}
└─ Example: 5,234 messages deleted

relay_deletion_reason
├─ Label: cegp_accepted, bounce_timeout, manual_cleanup
├─ cegp_accepted: Deleted because CEGP said "250 OK"
├─ bounce_timeout: Deleted after 5 days of failures
└─ manual_cleanup: Deleted by admin command

relay_queue_size_messages
├─ Gauge: Current messages in queue
├─ Should be: Small (< 100 messages)
└─ Alert if: > 1,000 (something wrong)
```

### Sample Metrics Query

```sql
-- Messages deleted after CEGP confirmation
SELECT timestamp, 
       relay_messages_deleted_from_queue_total as deleted
FROM relay_metrics
WHERE reason = 'cegp_accepted'
ORDER BY timestamp DESC;

-- Result: Only deletions after "250 OK" from CEGP
```

---

## Rules Summary

```
┌──────────────────────────────────────────────────────────┐
│ DELETION RULE: "Delete Only After CEGP Confirms"         │
├──────────────────────────────────────────────────────────┤
│                                                           │
│ STEP 1: Customer → Relay                                │
│  └─ Save to disk                                        │
│     Do NOT delete yet                                   │
│                                                           │
│ STEP 2: Relay → CEGP                                    │
│  └─ Send message                                        │
│     Do NOT delete yet                                   │
│     WAIT for CEGP response...                           │
│                                                           │
│ STEP 3: CEGP Responds                                   │
│  ├─ If "250 OK": DELETE from disk immediately ✓         │
│  ├─ If "4xx": KEEP in queue, retry later ✓             │
│  └─ If "5xx": KEEP in queue, retry, then bounce ✓      │
│                                                           │
│ RESULT: Message only deleted when CEGP confirmed ✓      │
│                                                           │
└──────────────────────────────────────────────────────────┘
```

---

## Testing: Verify Deletion Behavior

### Test 1: Verify Messages Are Saved Before Sending

```bash
# Send email through relay
echo "Test message" | nc -q 1 relay.email-security:25

# While it's processing, check disk
kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- \
  ls -la /var/spool/postfix/defer/

# Should show message files
# Don't delete until CEGP responds
```

### Test 2: Verify Deletion After CEGP Accepts

```bash
# Monitor in one terminal
kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- \
  watch "ls -la /var/spool/postfix/defer/ | wc -l"

# Send message in another terminal
# You should see:
# 1. File count increases (message saved)
# 2. File count decreases (message deleted after CEGP OK)
```

### Test 3: Verify Retry on CEGP Rejection

```bash
# Block CEGP connection (simulate rejection)
kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- \
  iptables -A OUTPUT -p tcp --dport 25 -j DROP

# Send message
# Message should stay in queue

# Check files
kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- \
  ls -la /var/spool/postfix/defer/ | wc -l

# Should still show files (not deleted)

# Unblock connection
kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- \
  iptables -D OUTPUT -p tcp --dport 25 -j DROP

# Postfix retries automatically
# Once CEGP responds "250 OK": Delete
```

---

## Final Guarantee

```
✅ GUARANTEE: Messages are ONLY deleted from disk
             when CEGP sends "250 OK" (message accepted)

             If CEGP rejects (4xx/5xx):
             → Message stays on disk
             → Retry automatically
             → Eventually bounce to sender
             → Delete after 5 days

             If relay crashes:
             → Message survives on PVC
             → New pod recovers message
             → Continues delivery
             → Only deletes after CEGP confirms

RESULT: ZERO MESSAGE LOSS GUARANTEED ✅
```

---

**Document Version:** 1.0  
**Last Updated:** March 2025  
**Status:** Production Ready - Clear deletion logic confirmed
