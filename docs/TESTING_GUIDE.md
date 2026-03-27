# CEGP SMTP Relay Testing Guide

## Prerequisites

Before testing, ensure your CEGP SMTP relay is deployed and running:

```bash
# Check if pods are running
k0s kubectl get pods -n email-security

# If needed, ensure local-path provisioner exists:
k0s kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml
# Deploy using installer-generated manifest:
./install.sh
```

## Step 1: Basic Health Check

### 1.1 Verify Deployment Status
```bash
# Check all resources
k0s kubectl get all -n email-security

# Check pod logs
k0s kubectl logs -l app=cegp-smtp-relay -n email-security --tail=50

# Check service and get LoadBalancer IP
k0s kubectl get svc cegp-smtp-relay -n email-security
```

### 1.2 Get External IP
```bash
# Get the LoadBalancer IP (save this for all tests)
RELAY_IP=$(k0s kubectl get svc cegp-smtp-relay -n email-security -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "SMTP Relay IP: $RELAY_IP"

# If LoadBalancer IP is pending, use NodePort instead:
NODE_IP=$(k0s kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(k0s kubectl get svc cegp-smtp-relay -n email-security -o jsonpath='{.spec.ports[?(@.name=="smtp")].nodePort}')
echo "Alternative: $NODE_IP:$NODE_PORT"
```

## Step 2: Network Connectivity Tests

### 2.1 Basic Port Test
```bash
# Test if SMTP port 25 is accessible
nc -zv $RELAY_IP 25

# Test all SMTP ports
for port in 25 587 465; do
  echo "Testing port $port..."
  nc -zv $RELAY_IP $port
done
```

### 2.2 SMTP Banner Test
```bash
# Test SMTP banner response
echo "QUIT" | nc $RELAY_IP 25
```

Expected output should include:
```
220 relay.email-security.svc.cluster.local ESMTP Trend Micro CEGP Relay
221 2.0.0 Bye
```

## Step 3: SMTP Protocol Tests

### 3.1 Manual SMTP Commands
```bash
# Interactive SMTP session
telnet $RELAY_IP 25

# In the telnet session, type these commands:
EHLO test.com
MAIL FROM: <test@example.com>
RCPT TO: <recipient@yourdomain.com>
DATA
Subject: Test Email from CEGP Relay
From: test@example.com
To: recipient@yourdomain.com

This is a test email from the CEGP SMTP relay.
.
QUIT
```

### 3.2 Automated SMTP Test Script
Create and run this test script:

```bash
# Create test script
cat > smtp-test.sh << 'EOF'
#!/bin/bash
RELAY_IP=${1:-"YOUR_RELAY_IP"}
TEST_FROM=${2:-"test@example.com"}
TEST_TO=${3:-"recipient@yourdomain.com"}

echo "Testing SMTP relay at $RELAY_IP"
echo "From: $TEST_FROM"
echo "To: $TEST_TO"
echo "---"

{
  echo "EHLO test.com"
  sleep 1
  echo "MAIL FROM: <$TEST_FROM>"
  sleep 1
  echo "RCPT TO: <$TEST_TO>"
  sleep 1
  echo "DATA"
  sleep 1
  echo "Subject: CEGP Relay Test - $(date)"
  echo "From: $TEST_FROM"
  echo "To: $TEST_TO"
  echo "Date: $(date -R)"
  echo ""
  echo "This is an automated test email from the CEGP SMTP relay."
  echo "Timestamp: $(date)"
  echo "Test ID: $(uuidgen 2>/dev/null || echo $RANDOM)"
  echo "."
  sleep 1
  echo "QUIT"
} | nc $RELAY_IP 25

echo "---"
echo "Test completed. Check logs for results."
EOF

chmod +x smtp-test.sh

# Run the test
./smtp-test.sh $RELAY_IP test@yourcompany.com recipient@yourcompany.com
```

### 3.3 Installer Throttled Test (Recommended)
Use the built-in menu option to avoid upstream rate limits:

```bash
./install.sh
# Select option 11: Send throttled test messages
```

The menu prompts for:
- source email
- destination email
- message count
- delay between messages (default 2 seconds)

## Step 4: Load and Performance Tests

### 4.1 Multiple Connection Test
```bash
# Test concurrent connections
for i in {1..5}; do
  echo "Connection test $i" &
  {
    echo "EHLO test$i.com"
    sleep 1
    echo "QUIT"
  } | nc $RELAY_IP 25 &
done
wait
echo "Concurrent connection test completed"
```

### 4.2 Throughput Test
```bash
# Send multiple emails quickly
for i in {1..10}; do
  echo "Sending test email $i"
  {
    echo "EHLO test.com"
    echo "MAIL FROM: <load-test-$i@example.com>"
    echo "RCPT TO: <recipient@yourdomain.com>"
    echo "DATA"
    echo "Subject: Load Test Email $i"
    echo ""
    echo "Load test email number $i sent at $(date)"
    echo "."
    echo "QUIT"
  } | nc $RELAY_IP 25 &
  
  # Small delay to avoid overwhelming
  sleep 0.5
done
wait
```

### 4.3 Monitor Auto-Scaling
```bash
# Watch HPA during load test
k0s kubectl get hpa cegp-smtp-relay-hpa -n email-security -w &

# Watch pod scaling
k0s kubectl get pods -n email-security -w &

# Run load test and observe scaling
# (Run the throughput test above while watching)
```

## Step 5: Monitoring and Logging

### 5.1 Real-time Log Monitoring
```bash
# Follow all relay logs
k0s kubectl logs -f -l app=cegp-smtp-relay -n email-security

# Follow logs from specific pod
POD_NAME=$(k0s kubectl get pods -n email-security -l app=cegp-smtp-relay -o jsonpath='{.items[0].metadata.name}')
k0s kubectl logs -f $POD_NAME -n email-security
```

### 5.2 Check Message Queue
```bash
# Check Postfix queue status
k0s kubectl exec -it deployment/cegp-smtp-relay -n email-security -- postqueue -p

# Check queue statistics
k0s kubectl exec -it deployment/cegp-smtp-relay -n email-security -- postqueue -j

# Check mail logs inside container
k0s kubectl exec -it deployment/cegp-smtp-relay -n email-security -- tail -f /var/log/mail.log
```

### 5.3 Resource Usage
```bash
# Check CPU and memory usage
k0s kubectl top pods -n email-security

# Check detailed resource usage
k0s kubectl describe pods -l app=cegp-smtp-relay -n email-security
```

## Step 6: Integration Tests

### 6.1 Test with Real Application
```bash
# Configure your application to use the SMTP relay
# Application SMTP settings:
# Host: $RELAY_IP
# Port: 25 (or 587 for submission)
# Authentication: None (if within permitted networks)
# TLS: Optional (currently disabled)

# Send test email from your application
# Monitor logs: k0s kubectl logs -f -l app=cegp-smtp-relay -n email-security
```

### 6.2 CEGP Console Integration
1. **Add Domain in CEGP Console:**
   - Navigate to Email Security → Domains
   - Add your email domain
   - Set Type: "User-defined mail servers"
   - Server: `$RELAY_IP:25`
   - Preference: 10

2. **Test Email Flow:**
   - Send email from application → Relay → CEGP → Final destination
   - Check CEGP logs for processing
   - Verify delivery to final recipient

## Step 7: Failure and Recovery Tests

### 7.1 Pod Restart Test
```bash
# Delete a pod and verify it restarts
POD_NAME=$(k0s kubectl get pods -n email-security -l app=cegp-smtp-relay -o jsonpath='{.items[0].metadata.name}')
k0s kubectl delete pod $POD_NAME -n email-security

# Watch pod recreation
k0s kubectl get pods -n email-security -w

# Verify service continues working
./smtp-test.sh $RELAY_IP
```

### 7.2 Persistent Storage Test
```bash
# Send email and check it's queued
./smtp-test.sh $RELAY_IP test@example.com nonexistent@invalid-domain.com

# Check queue has the message
k0s kubectl exec -it deployment/cegp-smtp-relay -n email-security -- postqueue -p

# Restart pod and verify message persists
k0s kubectl delete pod $POD_NAME -n email-security
sleep 30
k0s kubectl exec -it deployment/cegp-smtp-relay -n email-security -- postqueue -p
```

## Step 8: Security Tests

### 8.1 Access Control Test
```bash
# Test from unauthorized IP (should be rejected if IP filtering is enabled)
# This test assumes you've configured permit-ips.conf

# Test relay restrictions
{
  echo "EHLO test.com"
  echo "MAIL FROM: <test@example.com>"
  echo "RCPT TO: <external@gmail.com>"  # Should be rejected if not in relay domains
  echo "QUIT"
} | nc $RELAY_IP 25
```

### 8.2 Rate Limiting Test
```bash
# Test rate limits by sending many emails quickly
for i in {1..50}; do
  {
    echo "EHLO test.com"
    echo "MAIL FROM: <rate-test-$i@example.com>"
    echo "RCPT TO: <recipient@yourdomain.com>"
    echo "DATA"
    echo "Subject: Rate Test $i"
    echo ""
    echo "Rate limit test $i"
    echo "."
    echo "QUIT"
  } | nc $RELAY_IP 25 &
done
wait
```

## Troubleshooting Common Issues

### Issue: Connection Refused
```bash
# Check if service is running
k0s kubectl get svc -n email-security
k0s kubectl get endpoints -n email-security

# Check pod status
k0s kubectl describe pods -l app=cegp-smtp-relay -n email-security
```

### Issue: Messages Not Delivered
```bash
# Check Postfix logs
k0s kubectl logs -l app=cegp-smtp-relay -n email-security | grep -i error

# Check message queue
k0s kubectl exec -it deployment/cegp-smtp-relay -n email-security -- postqueue -p
```

### Issue: Performance Problems
```bash
# Check resource limits
k0s kubectl describe pods -l app=cegp-smtp-relay -n email-security | grep -A 10 "Limits\|Requests"

# Check HPA status
k0s kubectl describe hpa cegp-smtp-relay-hpa -n email-security
```

## Expected Results

✅ **Successful Test Results:**
- SMTP banner shows "Trend Micro CEGP Relay"
- EHLO command returns supported features
- Test emails are accepted (250 OK responses)
- Logs show successful message processing
- Queue shows messages being processed
- Auto-scaling works under load
- Pod restarts don't lose queued messages

❌ **Failed Test Indicators:**
- Connection timeouts or refused connections
- 5xx SMTP error codes
- Messages stuck in queue
- Pod crash loops
- Resource exhaustion

## Next Steps

After successful testing:
1. Configure domain and IP restrictions in ConfigMaps
2. Set up TLS certificates for production
3. Configure monitoring and alerting
4. Set up backup for persistent storage
5. Document operational procedures