# Kubernetes Deployment Troubleshooting Guide

## Common Issues and Solutions

### 1. ServiceMonitor CRD Missing

**Error:**
```
resource mapping not found for name: "cegp-smtp-relay" namespace: "email-security" from "kubernetes/kubernetes-deployment-persistent.yaml": no matches for kind "ServiceMonitor" in version "monitoring.coreos.com/v1"
ensure CRDs are installed first
```

**Solution:**
ServiceMonitor requires Prometheus Operator. Either:

**Option A: Install Prometheus Operator**
```bash
# Add Prometheus Community Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus Operator
helm install prometheus-operator prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

**Option B: Use the simple deployment (recommended for testing)**
```bash
k0s kubectl apply -f kubernetes/kubernetes-deployment-simple.yaml
```

### 2. Invalid Base64 Data in Secret

**Error:**
```
Error from server (BadRequest): error when creating "kubernetes/kubernetes-deployment-persistent.yaml": Secret in version "v1" cannot be handled as a Secret: illegal base64 data at input byte 264
```

**Solution:**
Generate proper TLS certificates:

```bash
# Generate self-signed certificates
./scripts/generate-tls-certs.sh

# Or create the secret manually
kubectl create secret tls relay-tls-certs \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  --namespace=email-security
```

### 3. StorageClass Issues

**Error:**
```
persistentvolumeclaim "relay-queue-storage" is invalid: spec.storageClassName: Invalid value: "relay-fast-storage": storageclass.storage.k8s.io "relay-fast-storage" not found
```

**Solution:**
Check available StorageClasses and update the deployment:

```bash
# Check available StorageClasses
k0s kubectl get storageclass

# Common StorageClasses in k0s:
# - local-path (Rancher local-path-provisioner)
# - standard (if using cloud provider)

# Update the StorageClass in the YAML file or use the simple deployment
```

### 4. kubectl Command Not Found

**Error:**
```
Command 'kubectl' not found, but can be installed with: snap install kubectl
```

**Solution:**
For k0s clusters, use `k0s kubectl` instead of `kubectl`:

```bash
# Instead of: kubectl apply -f file.yaml
k0s kubectl apply -f kubernetes/kubernetes-deployment-simple.yaml

# Create an alias for convenience
alias kubectl='k0s kubectl'
```

### 5. Image Pull Issues

**Error:**
```
Failed to pull image "company-registry/cegp-smtp-relay:1.0.0": rpc error: code = Unknown desc = Error response from daemon: pull access denied
```

**Solution:**
The custom image doesn't exist yet. Use a standard postfix image:

```bash
# The simple deployment uses: postfix:latest
# Or use: boky/postfix:latest (popular postfix container)

# Update the image in the deployment:
image: boky/postfix:latest
```

## Deployment Verification

After successful deployment, verify everything is working:

```bash
# Check namespace
k0s kubectl get ns email-security

# Check all resources
k0s kubectl get all -n email-security

# Check persistent volumes
k0s kubectl get pvc -n email-security
k0s kubectl get pv

# Check pod logs
k0s kubectl logs -l app=cegp-smtp-relay -n email-security

# Check service
k0s kubectl get svc cegp-smtp-relay -n email-security

# Test SMTP connectivity
k0s kubectl exec -it deployment/cegp-smtp-relay -n email-security -- telnet localhost 25
```

## Configuration Updates

### Update Relay Domains
```bash
k0s kubectl patch configmap relay-policy -n email-security \
  --type merge -p '{"data":{"domains.conf":"example.com\ncompany.org"}}'
```

### Update Permitted IPs
```bash
k0s kubectl patch configmap relay-policy -n email-security \
  --type merge -p '{"data":{"permit-ips.conf":"10.0.0.0/8\n192.168.1.0/24"}}'
```

### Restart Deployment
```bash
k0s kubectl rollout restart deployment cegp-smtp-relay -n email-security
```

## Monitoring and Logs

### View Real-time Logs
```bash
# All pods
k0s kubectl logs -f -l app=cegp-smtp-relay -n email-security

# Specific pod
k0s kubectl logs -f cegp-smtp-relay-<pod-id> -n email-security
```

### Check Resource Usage
```bash
k0s kubectl top pods -n email-security
k0s kubectl top nodes
```

### Debug Pod Issues
```bash
# Describe pod
k0s kubectl describe pod cegp-smtp-relay-<pod-id> -n email-security

# Get events
k0s kubectl get events -n email-security --sort-by='.lastTimestamp'

# Shell into pod
k0s kubectl exec -it cegp-smtp-relay-<pod-id> -n email-security -- /bin/bash
```

## Performance Tuning

### Scale Deployment
```bash
# Manual scaling
k0s kubectl scale deployment cegp-smtp-relay --replicas=5 -n email-security

# Check HPA status
k0s kubectl get hpa -n email-security
k0s kubectl describe hpa cegp-smtp-relay-hpa -n email-security
```

### Storage Expansion
```bash
# Check if StorageClass supports expansion
k0s kubectl get storageclass relay-fast-storage -o yaml | grep allowVolumeExpansion

# Expand PVC (if supported)
k0s kubectl patch pvc relay-queue-storage -n email-security \
  -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
```

## Clean Up

### Remove Deployment
```bash
k0s kubectl delete -f kubernetes/kubernetes-deployment-simple.yaml
```

### Remove Namespace (removes everything)
```bash
k0s kubectl delete namespace email-security
```

### Remove PV (if needed)
```bash
k0s kubectl get pv
k0s kubectl delete pv <pv-name>
```

## Next Steps

1. **Test SMTP functionality** - Send test emails through the relay
2. **Configure CEGP** - Add the LoadBalancer IP to CEGP console
3. **Set up monitoring** - Install Prometheus Operator if needed
4. **Production certificates** - Replace self-signed certs with real ones
5. **Backup strategy** - Plan for persistent volume backups