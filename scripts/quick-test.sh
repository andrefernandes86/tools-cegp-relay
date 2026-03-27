#!/bin/bash
# Quick Test Script for CEGP SMTP Relay
# Usage: ./quick-test.sh [relay-ip] [from-email] [to-email]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get parameters or use defaults
RELAY_IP=${1:-$(k0s kubectl get svc cegp-smtp-relay -n email-security -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)}
FROM_EMAIL=${2:-"test@example.com"}
TO_EMAIL=${3:-"recipient@yourdomain.com"}

if [ -z "$RELAY_IP" ] || [ "$RELAY_IP" = "null" ]; then
    print_warning "LoadBalancer IP not available, trying NodePort..."
    NODE_IP=$(k0s kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    NODE_PORT=$(k0s kubectl get svc cegp-smtp-relay -n email-security -o jsonpath='{.spec.ports[?(@.name=="smtp")].nodePort}')
    RELAY_IP="$NODE_IP"
    SMTP_PORT="$NODE_PORT"
else
    SMTP_PORT="25"
fi

echo "=========================================="
echo "CEGP SMTP Relay Quick Test"
echo "=========================================="
echo "Relay IP: $RELAY_IP"
echo "SMTP Port: $SMTP_PORT"
echo "From: $FROM_EMAIL"
echo "To: $TO_EMAIL"
echo "=========================================="

# Test 1: Check if pods are running
print_status "Checking pod status..."
POD_STATUS=$(k0s kubectl get pods -n email-security -l app=cegp-smtp-relay --no-headers 2>/dev/null | awk '{print $3}' | head -1)
if [ "$POD_STATUS" = "Running" ]; then
    print_success "Pods are running"
else
    print_error "Pods are not running (Status: $POD_STATUS)"
    print_status "Pod details:"
    k0s kubectl get pods -n email-security -l app=cegp-smtp-relay
    exit 1
fi

# Test 2: Check network connectivity
print_status "Testing network connectivity to $RELAY_IP:$SMTP_PORT..."
if timeout 5 nc -z $RELAY_IP $SMTP_PORT 2>/dev/null; then
    print_success "Port $SMTP_PORT is accessible"
else
    print_error "Cannot connect to $RELAY_IP:$SMTP_PORT"
    print_status "Checking service status..."
    k0s kubectl get svc cegp-smtp-relay -n email-security
    exit 1
fi

# Test 3: SMTP Banner Test
print_status "Testing SMTP banner..."
BANNER=$(timeout 5 sh -c "echo 'QUIT' | nc $RELAY_IP $SMTP_PORT" 2>/dev/null | head -1)
if echo "$BANNER" | grep -q "220.*ESMTP"; then
    print_success "SMTP banner received: $BANNER"
else
    print_error "Invalid or no SMTP banner received"
    echo "Received: $BANNER"
fi

# Test 4: EHLO Command Test
print_status "Testing EHLO command..."
EHLO_RESPONSE=$(timeout 10 sh -c "{
    echo 'EHLO test.com'
    sleep 2
    echo 'QUIT'
} | nc $RELAY_IP $SMTP_PORT" 2>/dev/null)

if echo "$EHLO_RESPONSE" | grep -q "250.*Hello"; then
    print_success "EHLO command successful"
else
    print_warning "EHLO command may have failed"
    echo "Response: $EHLO_RESPONSE"
fi

# Test 5: Send Test Email
print_status "Sending test email..."
EMAIL_RESPONSE=$(timeout 30 sh -c "{
    echo 'EHLO test.com'
    sleep 1
    echo 'MAIL FROM: <$FROM_EMAIL>'
    sleep 1
    echo 'RCPT TO: <$TO_EMAIL>'
    sleep 1
    echo 'DATA'
    sleep 1
    echo 'Subject: CEGP Relay Test - $(date)'
    echo 'From: $FROM_EMAIL'
    echo 'To: $TO_EMAIL'
    echo 'Date: $(date -R)'
    echo ''
    echo 'This is a test email from the CEGP SMTP relay.'
    echo 'Timestamp: $(date)'
    echo 'Test completed successfully.'
    echo '.'
    sleep 1
    echo 'QUIT'
} | nc $RELAY_IP $SMTP_PORT" 2>/dev/null)

if echo "$EMAIL_RESPONSE" | grep -q "250.*OK"; then
    print_success "Test email sent successfully"
else
    print_error "Failed to send test email"
    echo "Response: $EMAIL_RESPONSE"
fi

# Test 6: Check logs for the test email
print_status "Checking recent logs..."
RECENT_LOGS=$(k0s kubectl logs -l app=cegp-smtp-relay -n email-security --tail=10 --since=30s 2>/dev/null)
if echo "$RECENT_LOGS" | grep -q -i "test\|mail\|smtp"; then
    print_success "Recent activity found in logs"
    echo "Recent logs:"
    echo "$RECENT_LOGS" | tail -5
else
    print_warning "No recent activity in logs (this might be normal)"
fi

# Test 7: Check message queue
print_status "Checking message queue..."
QUEUE_STATUS=$(k0s kubectl exec -it deployment/cegp-smtp-relay -n email-security -- postqueue -p 2>/dev/null | grep -v "Mail queue is empty" || echo "empty")
if [ "$QUEUE_STATUS" = "empty" ]; then
    print_success "Message queue is empty (messages processed)"
else
    print_warning "Messages in queue:"
    echo "$QUEUE_STATUS"
fi

# Test 8: Resource usage
print_status "Checking resource usage..."
RESOURCE_USAGE=$(k0s kubectl top pods -n email-security -l app=cegp-smtp-relay --no-headers 2>/dev/null || echo "metrics not available")
if [ "$RESOURCE_USAGE" != "metrics not available" ]; then
    print_success "Resource usage:"
    echo "$RESOURCE_USAGE"
else
    print_warning "Resource metrics not available (metrics-server may not be configured)"
fi

echo "=========================================="
print_success "Quick test completed!"
echo "=========================================="

echo ""
echo "Next steps:"
echo "1. Configure your application to use SMTP server: $RELAY_IP:$SMTP_PORT"
echo "2. Add your domain to CEGP console with server: $RELAY_IP:25"
echo "3. Configure relay domains and permitted IPs in ConfigMaps"
echo "4. Monitor logs: k0s kubectl logs -f -l app=cegp-smtp-relay -n email-security"
echo ""
echo "For detailed testing, see: docs/TESTING_GUIDE.md"