# CEGP SMTP Relay Installation Guide

## Overview

The CEGP SMTP Relay now includes a comprehensive installation and management script (`install.sh`) that handles everything from initial deployment to ongoing monitoring and configuration management.

## Prerequisites

- **Kubernetes cluster** (local k0s/k3s or remote)
- **kubectl** or **k0s** command-line tool
- **git** for repository cloning
- **netcat (nc)** for connectivity testing
- **SSH access** (for remote deployments)

## Quick Installation

```bash
# Clone the repository
git clone https://github.com/andrefernandes86/tools-cegp-relay.git
cd tools-cegp-relay

# Run the installer
./install.sh
```

## Installation Process

### 1. Deployment Type Selection

Choose between:
- **Local deployment** - Deploy on the current machine's Kubernetes cluster
- **Remote deployment** - Deploy on a remote Kubernetes cluster via SSH

### 2. Scaling Configuration

Configure auto-scaling parameters:
- **Minimum replicas**: 2-20 (default: 3)
- **Maximum replicas**: Up to 20 (default: 20)
- **Auto-scaling**: Based on CPU and memory usage

### 3. CEGP Gateway Configuration

Set up the destination gateway:
- **CEGP destination**: Next-hop IP or FQDN
- **CEGP port**: Default `25`
- **TLS settings**: Configurable

### 4. Message Storage Location

Configure where temporary queue files are stored:
- **Default**: `/mnt/nfs/messages`
- **Behavior**: Each pod uses its own subdirectory under this path (safe multi-pod operation)

### 5. LoadBalancer IP Option (Local Clusters)

Optionally enable MetalLB from the installer:
- auto-installs MetalLB
- configures an address pool (example: `192.168.40.240-192.168.40.250`)
- allows `Service type: LoadBalancer` to get an external IP on bare-metal/local clusters

### 6. Security Configuration

#### Authorized Domains
Specify which email domains can send through the relay:
```
company.com
subsidiary.org
branch.local
```

#### Authorized IP Addresses
Define IP ranges allowed to connect (CIDR notation):
```
192.168.1.0/24
10.0.0.0/8
172.16.5.10/32
```

### 7. Rate Limiting

Configure message throughput limits:
- **Per IP per minute**: Default 2000 messages
- **Per recipient per minute**: Default 200 messages

## Remote Deployment Setup

For remote deployments, provide:
- **Server IP address**: Target Kubernetes cluster IP
- **Username**: SSH username
- **Password**: SSH password (or use key-based auth)

The installer will:
1. Set up SSH key authentication
2. Copy deployment files to remote server
3. Execute deployment commands remotely
4. Configure remote monitoring

## Post-Installation

After successful deployment:

### 1. Verify Status
```bash
./install.sh
# Select option 2: Show deployment status
```

### 2. Get LoadBalancer IP
The installer will display the external IP address for your SMTP relay.

### 3. Configure CEGP Console
1. Log into Trend Micro CEGP console
2. Navigate to Email Security → Domains
3. Add your domain
4. Set Type: "User-defined mail servers"
5. Server: `<LoadBalancer-IP>:25`
6. Preference: 10

### 4. Test the Deployment
```bash
./install.sh
# Select option 11: Send throttled test messages
```

## Management Features

### Real-time Monitoring
```bash
./install.sh
# Select option 3: Monitor real-time metrics
```

Displays:
- Active node count and health
- Message statistics (received/delivered per second)
- Resource usage (CPU/memory)
- Queue status
- Auto-scaling activity

### Configuration Management
```bash
./install.sh
# Select option 4: Manage configuration
```

Allows you to:
- Add/remove authorized domains
- Manage permitted IP addresses
- Update CEGP gateway settings
- Modify scaling parameters
- Adjust rate limiting
- Apply changes with zero downtime

### Log Monitoring
```bash
./install.sh
# Select option 5: View logs
```

### Manual Scaling
```bash
./install.sh
# Select option 7: Scale deployment
```

### Connection Information
```bash
./install.sh
# Select option 12: Show connection information
```

Shows:
- LoadBalancer IP/hostname with ports (if available)
- NodePort values
- All node internal IPs + direct `IP:NodePort` endpoints
- Configured allowed source networks and sender domains

## Configuration Files

The installer creates and manages:
- `config/deployment.conf` - Main configuration file
- `config/deployment-backup-*.conf` - Automatic backups
- `kubernetes/kubernetes-deployment-configured.yaml` - Generated deployment

## Troubleshooting

### Common Issues

#### 1. Pods Stuck in Pending
- Check node resources and events
- Check image pull and probe failures
- Verify queue storage path exists/is writable on nodes

#### 2. ImagePullBackOff
- Ensure internet connectivity
- Verify image name (`boky/postfix:latest`)
- Check container registry access

#### 3. Service Not Accessible
- Verify LoadBalancer configuration
- Check firewall rules
- Confirm service endpoints

### Debug Commands

```bash
# Check pod status
kubectl get pods -n email-security -o wide

# View pod logs
kubectl logs -l app=cegp-smtp-relay -n email-security

# Check events
kubectl get events -n email-security --sort-by='.lastTimestamp'

# Verify service
kubectl get svc cegp-smtp-relay -n email-security
```

## Advanced Configuration

### Custom Images
To use a custom SMTP relay image, modify:
```yaml
# In kubernetes/kubernetes-deployment-simple.yaml
image: your-registry/custom-postfix:tag
```

### TLS Certificates
Generate and apply TLS certificates:
```bash
./scripts/generate-tls-certs.sh
kubectl apply -f kubernetes/kubernetes-deployment-persistent.yaml
```

### Persistent Storage
The deployment stores queue data in the configured host path (default `/mnt/nfs/messages`), with one subdirectory per pod.
This enables multi-pod load balancing without shared queue file collisions.

### Network Policies
For enhanced security, apply network policies:
```bash
kubectl apply -f kubernetes/network-policies.yaml
```

## Backup and Recovery

### Configuration Backup
```bash
./install.sh
# Select option 8: Backup configuration
```

### Configuration Restore
```bash
./install.sh
# Select option 9: Restore configuration
```

### Message Queue Backup
Message queues are automatically persisted in PersistentVolumes.

## Uninstallation

To completely remove the deployment:
```bash
./install.sh
# Select option 10: Uninstall
```

This will:
- Delete all Kubernetes resources
- Remove configuration files
- Clean up persistent volumes
- Remove SSH keys (for remote deployments)

## Security Best Practices

1. **Restrict IP Access**: Always configure authorized IP ranges
2. **Domain Validation**: Specify exact domains, avoid wildcards
3. **Rate Limiting**: Set appropriate limits for your environment
4. **TLS Encryption**: Enable TLS for production deployments
5. **Network Segmentation**: Use network policies to isolate traffic
6. **Regular Updates**: Keep container images updated
7. **Monitor Logs**: Set up log aggregation and alerting

## Performance Tuning

### Scaling Parameters
- Start with 3 minimum replicas
- Set maximum based on expected load
- Monitor CPU/memory usage for optimal scaling

### Rate Limits
- Adjust based on CEGP gateway capacity
- Consider peak traffic patterns
- Monitor queue buildup

### Resource Allocation
```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 1Gi
```

## Support and Documentation

- **Installation Issues**: See `docs/KUBERNETES_TROUBLESHOOTING.md`
- **Testing Guide**: See `docs/TESTING_GUIDE.md`
- **Architecture Details**: See `docs/CEGP_Complete_Introduction.md`
- **Performance Tuning**: See `docs/LOAD_BALANCING_GUIDE.md`