#!/bin/bash
# Generate self-signed TLS certificates for CEGP SMTP Relay
# For production, replace with real certificates from your CA

set -e

CERT_DIR="./certs"
NAMESPACE="email-security"
SECRET_NAME="relay-tls-certs"

# Create certs directory
mkdir -p "$CERT_DIR"

echo "Generating self-signed TLS certificate for CEGP SMTP Relay..."

# Generate private key
openssl genrsa -out "$CERT_DIR/tls.key" 2048

# Generate certificate signing request
openssl req -new -key "$CERT_DIR/tls.key" -out "$CERT_DIR/tls.csr" -subj "/CN=relay.email-security.svc.cluster.local/O=CEGP Relay"

# Generate self-signed certificate (valid for 1 year)
openssl x509 -req -in "$CERT_DIR/tls.csr" -signkey "$CERT_DIR/tls.key" -out "$CERT_DIR/tls.crt" -days 365

# Clean up CSR
rm "$CERT_DIR/tls.csr"

echo "Certificates generated in $CERT_DIR/"
echo "  - tls.key (private key)"
echo "  - tls.crt (certificate)"

# Create or update Kubernetes secret
echo "Creating/updating Kubernetes TLS secret..."
kubectl create secret tls "$SECRET_NAME" \
  --cert="$CERT_DIR/tls.crt" \
  --key="$CERT_DIR/tls.key" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ TLS secret '$SECRET_NAME' created/updated in namespace '$NAMESPACE'"
echo ""
echo "⚠️  IMPORTANT: These are self-signed certificates for testing only!"
echo "   For production, replace with certificates from your Certificate Authority."
echo ""
echo "To verify the secret:"
echo "  kubectl get secret $SECRET_NAME -n $NAMESPACE"
echo "  kubectl describe secret $SECRET_NAME -n $NAMESPACE"