# CEGP + Relay Container Setup - Quick Reference

## Part 1: CEGP Console Configuration (Trend Micro Side)

### Navigate to Add Domain

**Path:** Email and Collaboration Security Operations → Cloud Email Gateway Protection → Domains

```
┌─────────────────────────────────────────────────┐
│ Domains Screen                                   │
├─────────────────────────────────────────────────┤
│ [Add Domain Button]                              │
│                                                  │
│ Existing Domains:                                │
│ ○ example.org (Office 365)                      │
│ ○ test.local (Google Workspace)                 │
│ ○ company.com (← We're adding this)              │
└─────────────────────────────────────────────────┘
```

### Step 1: Add Domain Dialog

```
┌────────────────────────────────────────────────┐
│ Add Domain                                     │
├────────────────────────────────────────────────┤
│ Domain Name: [company.com____________]          │
│                                                 │
│ Seat Count: [100___]                            │
│                                                 │
│ Select Outbound Server Type:                    │
│ ○ Office 365                                    │
│ ○ Google Workspace                              │
│ ⦿ User-defined mail servers  ← SELECT THIS    │
│                                                 │
│ [Add Domain Button]                             │
└────────────────────────────────────────────────┘
```

### Step 2: Configure Outbound Servers

After domain is added, go to: **Domains → [company.com] → Edit → Outbound Servers**

```
┌────────────────────────────────────────────────────────┐
│ Outbound Servers Configuration                         │
├────────────────────────────────────────────────────────┤
│                                                         │
│ Primary Relay Server:                                   │
│ ┌─────────────────────────────────────────────────┐   │
│ │ Recipient:          [*________________]          │   │
│ │ IP/FQDN:           [relay.email-                │   │
│ │                     security.svc.               │   │
│ │                     cluster.local___]            │   │
│ │ Port:              [25_]                         │   │
│ │ Preference:        [10_]  ← Lower = Higher Pri  │   │
│ │ [Delete] [Test]                                 │   │
│ └─────────────────────────────────────────────────┘   │
│                                                         │
│ Secondary Relay Server (Optional):                      │
│ ┌─────────────────────────────────────────────────┐   │
│ │ Recipient:          [*________________]          │   │
│ │ IP/FQDN:           [backup-relay.company.      │   │
│ │                     local________________]       │   │
│ │ Port:              [25_]                         │   │
│ │ Preference:        [20_]  ← Higher = Fallback   │   │
│ │ [Delete] [Test]                                 │   │
│ └─────────────────────────────────────────────────┘   │
│                                                         │
│ [+ Add Another Server]                                  │
│                                                         │
│ Send Test Message to: [admin@company.com_____]         │
│                                                         │
│ [Test Connection] [Save]                               │
└────────────────────────────────────────────────────────┘
```

**Fill in the form:**

| Field | Value | Notes |
|-------|-------|-------|
| **Recipient** | `*` | Wildcard = accept all @company.com |
| **IP/FQDN** | `relay.email-security.svc.cluster.local` OR `relay.company.local` (via DNS) | Must match the relay container's external IP or FQDN |
| **Port** | `25` | Standard SMTP port |
| **Preference** | `10` | Lower number = higher priority. This is primary. |

### Step 3: Test Outbound Server Connection

Click **[Test Connection]**

```
Expected Result:

✓ Connection successful to relay.email-security.svc.cluster.local:25
  (or your DNS FQDN)

This verifies:
- CEGP can reach the relay container
- Relay is accepting SMTP connections
- Firewall/network path is open
```

### Step 4: Send Test Message

In **"Send Test Message to"** field, enter an email address you monitor:

```
[admin@company.com_____]  [Send Test]

Expected Result:
- Message sent through CEGP
- Scanned by CEGP threat engine
- Relayed through this container
- Arrives at admin@company.com inbox
- Check headers: "X-TrendMicro-Scanned: Yes" or similar
```

---

## Part 2: Relay Container Configuration (Your Infrastructure)

### Deploy Kubernetes Manifests

```bash
# Create namespace and all resources
kubectl apply -f kubernetes-deployment.yaml

# Verify deployment
kubectl get pods -n email-security

# Expected output:
# NAME                                  READY   STATUS    RESTARTS
# cegp-smtp-relay-abc123-xyz789         1/1     Running   0
# cegp-smtp-relay-def456-pqr012         1/1     Running   0
# cegp-smtp-relay-ghi789-stu345         1/1     Running   0
```

### Expose Relay to CEGP

**Option A: Kubernetes LoadBalancer (Recommended for external CEGP)**

```yaml
# Already in kubernetes-deployment.yaml
apiVersion: v1
kind: Service
metadata:
  name: cegp-smtp-relay
  namespace: email-security
spec:
  type: LoadBalancer
  loadBalancerSourceRanges:
    - 150.70.149.0/27      # CEGP's IP ranges
    - 150.70.149.32/27
    # ... (add all CEGP regional IPs)
  selector:
    app: cegp-smtp-relay
  ports:
    - port: 25
      targetPort: 25
      protocol: TCP
```

Get the external IP:
```bash
kubectl get svc -n email-security cegp-smtp-relay

# Expected output:
# NAME               TYPE           CLUSTER-IP      EXTERNAL-IP
# cegp-smtp-relay    LoadBalancer   10.96.1.50      203.0.113.100   ← Use this IP in CEGP
```

Use `203.0.113.100` (external IP) in CEGP console.

**Option B: Kubernetes ClusterIP + DNS (For CEGP in same cluster)**

```bash
# Get the service IP
kubectl get svc -n email-security cegp-smtp-relay

# Expected output:
# cegp-smtp-relay   ClusterIP   10.96.1.50   <none>   25/TCP
```

In CEGP, configure: `cegp-smtp-relay.email-security.svc.cluster.local` (Kubernetes DNS)

### Configure Relay Domains

The relay must allow only YOUR domains to be relayed:

```bash
kubectl patch configmap relay-policy -n email-security \
  --type merge -p '{"data":{"domains.conf":"company.com\nsubsidiary.org"}}'

# Verify
kubectl get configmap relay-policy -n email-security -o jsonpath='{.data.domains\.conf}'

# Output:
# company.com
# subsidiary.org
```

### Configure CEGP IP Authorization

The relay must accept connections ONLY from CEGP:

```bash
kubectl patch configmap relay-policy -n email-security \
  --type merge -p '{"data":{"permit-ips.conf":"150.70.149.0/27\n150.70.149.32/27\n150.70.236.0/24\n150.70.239.0/24\n216.99.131.0/24\n216.104.4.0/24\n216.104.20.0/24"}}'

# Or if CEGP is in same cluster:
kubectl patch configmap relay-policy -n email-security \
  --type merge -p '{"data":{"permit-ips.conf":"10.0.0.0/8"}}'

# Verify
kubectl get configmap relay-policy -n email-security -o jsonpath='{.data.permit-ips\.conf}'
```

### Verify Metrics & Logs

```bash
# Watch logs in real-time
kubectl logs -f deployment/cegp-smtp-relay -n email-security

# Check metrics (port-forward to prometheus endpoint)
kubectl port-forward svc/cegp-smtp-relay 9090:9090 -n email-security &

# Query metrics
curl http://localhost:9090/metrics | grep relay_messages

# Expected output (after CEGP sends test message):
# relay_messages_received_total{domain="company.com",src_ip="150.70.149.5"} 1
# relay_messages_delivered_total{status="success"} 1
```

---

## Part 3: End-to-End Message Flow

### Message 1: Customer Sends Outbound Email

```
Timeline:

1. User (alice@company.com) composes email to bob@gmail.com
2. User submits to Company Exchange Server
3. Exchange server route logic:
   - Domain "gmail.com" → Not local → Send to relay
   OR
   - Company policy: "All outbound through CEGP" → Send to CEGP endpoint
```

### Message 2: CEGP Receives Outbound Email

```
Timeline:

4. Message sent to: relay.mx.trendmicro.com (CEGP endpoint)
   OR configured outbound smart host in Exchange

5. CEGP receives message from company.com
   - Checks against policies
   - Scans for malware, phishing, DLP
   - Cleans attachments if needed
   - Modifies headers (adds X-TrendMicro-Scanned header)
   - Applies compliance actions

6. CEGP looks up: "Which outbound server for company.com?"
   - Consults domain configuration
   - Finds: "User-defined mail servers → relay.email-security.svc.cluster.local:25"

7. CEGP connects to relay container at port 25
```

### Message 3: Relay Container Accepts Message

```
Timeline:

8. Relay container receives SMTP connection
   - Source IP: 150.70.149.5 (CEGP endpoint)

9. EHLO/AUTH negotiation
   - No authentication required (internal relay)

10. MAIL FROM: <alice@company.com>
    - Relay validates: "company.com" in domains.conf ✓
    - Relay validates: "150.70.149.5" in permit-ips.conf ✓

11. RCPT TO: <bob@gmail.com>
    - Relay checks rate limits per IP (CEGP's IP)
    - Relay checks rate limits per recipient (bob@gmail.com)
    - All checks pass ✓

12. DATA (message body)
    - Relay receives message (already scanned by CEGP)

13. Relay responds: "250 OK Message queued"
    - Message stored in /var/spool/postfix/
    - Relay returns control to CEGP
```

### Message 4: Relay Delivers to Final Destination

```
Timeline:

14. Relay's queue manager picks up message
    - Destination: bob@gmail.com (domain = gmail.com)

15. Relay performs DNS MX lookup for gmail.com
    - Result: gmail.com mail servers (e.g., 142.251.41.5)

16. Relay connects to gmail.com SMTP server
    - EHLO/AUTH (if required)

17. Relay sends:
    - MAIL FROM: <alice@company.com>
    - RCPT TO: <bob@gmail.com>
    - DATA (full message with CEGP scan headers)

18. Gmail's server responds: "250 OK Message accepted"

19. Bob receives email in Gmail inbox
    - Email was scanned by CEGP ✓
    - Email was relayed through company container ✓
    - Headers show Trend Micro scan status
```

---

## Part 4: Troubleshooting Checklist

### Issue: CEGP Reports "Connection Refused"

**Step 1:** Verify Relay is Running
```bash
kubectl get pods -n email-security
kubectl describe pod <pod-name> -n email-security
```

**Step 2:** Check Service Exposure
```bash
# Get service IP
kubectl get svc -n email-security cegp-smtp-relay

# Verify it's accessible from outside cluster (if external CEGP)
curl telnet://<EXTERNAL-IP>:25
```

**Step 3:** Verify Firewall Rules
```bash
# Check security groups / firewall
# Port 25 (SMTP) must be open from CEGP IP ranges to relay service
```

**Step 4:** Check Logs
```bash
kubectl logs deployment/cegp-smtp-relay -n email-security | grep "connection\|accept"
```

### Issue: CEGP Test Message Fails with "Relay Access Denied"

**Step 1:** Check domains.conf
```bash
kubectl get configmap relay-policy -n email-security -o jsonpath='{.data.domains\.conf}'

# Should contain "company.com"
# If empty or missing → update it
kubectl patch configmap relay-policy -n email-security \
  --type merge -p '{"data":{"domains.conf":"company.com"}}'
```

**Step 2:** Check CEGP's Source IP
```bash
# View pod logs for connection attempts
kubectl logs -f deployment/cegp-smtp-relay -n email-security | grep "src_ip\|connection"

# Look for the IP connecting from CEGP
```

**Step 3:** Update Permit List if Needed
```bash
kubectl patch configmap relay-policy -n email-security \
  --type merge -p '{"data":{"permit-ips.conf":"<CEGP-IP>/32"}}'
```

### Issue: Test Message Accepted but Never Arrives

**Step 1:** Check Relay Queue
```bash
kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- postqueue -p

# Shows queued messages
# If many are queued → destination unreachable
```

**Step 2:** Check Outbound Connectivity
```bash
kubectl exec -it cegp-smtp-relay-<pod> -n email-security -- bash

# Inside pod:
nc -zv gmail.com 25
nslookup gmail.com
```

**Step 3:** Check Delivery Logs
```bash
kubectl logs cegp-smtp-relay-<pod> -n email-security | grep "bob@gmail.com\|delivery"
```

---

## Part 5: Maintenance & Operations

### Monitor Relay Health

```bash
# Watch live metrics
watch -n 2 'kubectl port-forward svc/cegp-smtp-relay 9090:9090 & sleep 1 && curl -s http://localhost:9090/metrics | grep relay_ && kill %1'

# Or create Prometheus scrape job:
scrape_configs:
  - job_name: 'cegp-relay'
    static_configs:
      - targets: ['relay.email-security.svc.cluster.local:9090']
```

### Scale During High Volume

```bash
# Auto-scaling is enabled, but manual scale if needed:
kubectl scale deployment cegp-smtp-relay --replicas=10 -n email-security

# Watch scale progress:
kubectl get deployment cegp-smtp-relay -n email-security -w
```

### Update Relay Configuration

```bash
# Add new domain
CURRENT=$(kubectl get configmap relay-policy -n email-security -o jsonpath='{.data.domains\.conf}')
kubectl patch configmap relay-policy -n email-security \
  --type merge -p "{\"data\":{\"domains.conf\":\"$CURRENT\nnew-domain.org\"}}"

# Configuration updates are hot-reloaded (no pod restart needed)
```

### View All Relay Configuration

```bash
kubectl get configmap relay-policy -n email-security -o yaml
kubectl get secret relay-tls-certs -n email-security -o yaml
kubectl get deployment cegp-smtp-relay -n email-security -o yaml
```

---

## Part 6: Summary of Changes Required

### In CEGP Console
- [ ] Add domain with "User-Defined Mail Servers" option
- [ ] Configure outbound server: IP/FQDN of relay container
- [ ] Set port to 25
- [ ] Set preference value
- [ ] Test connection
- [ ] Send test message

### In Your Infrastructure
- [ ] Deploy Kubernetes manifests
- [ ] Expose relay via LoadBalancer or DNS
- [ ] Configure relay-policy ConfigMap with your domains
- [ ] Configure relay-policy ConfigMap with CEGP IP ranges
- [ ] Verify logs showing successful CEGP connections
- [ ] Monitor metrics for message delivery

### Expected Result
✓ Messages sent through your mail system
✓ Scanned by CEGP
✓ Relayed through this container
✓ Delivered to final destination
✓ Rate limits enforced
✓ Auto-scaling handles load spikes
✓ Complete audit trail in logs & metrics

---

**Document Version:** 1.0  
**Last Updated:** March 2025
