# CEGP SMTP Relay Container - Complete Solution Index

## 📚 Documentation Overview

This package contains everything needed to understand, deploy, and manage a production-ready SMTP relay container for Trend Micro's Cloud Email Gateway Protection (CEGP).

---

## 📖 Reading Order

### For New Users (Start Here)

1. **CEGP_Complete_Introduction.md** ⭐ **START HERE**
   - Executive summary
   - What the application does
   - Step-by-step message flow with examples
   - 7-phase lifecycle explanation
   - Scaling scenarios
   - Key features & benefits

2. **CEGP_Architecture_Diagrams.md**
   - Visual diagrams of the system
   - High-level architecture
   - Message state transitions
   - CEGP console configuration UI walkthrough
   - Rate limiting examples
   - Data flow diagrams

3. **CEGP_User_Defined_Mail_Servers.md**
   - Explains the CEGP integration model
   - Product specifications from Trend Micro
   - Rate limits and message rules
   - Configuration management
   - Compliance & standards

### For Implementation

4. **CEGP_Quick_Reference.md**
   - Quick deployment steps
   - CEGP console configuration
   - Kubernetes deployment
   - Configuration examples
   - End-to-end message flow
   - Troubleshooting checklist

5. **LOAD_BALANCING_GUIDE.md**
   - All load balancing options
   - Kubernetes Service LB (default)
   - Multi-region setup
   - HAProxy advanced configuration
   - Monitoring metrics
   - Troubleshooting load distribution

### For Deployment & Operations

6. **kubernetes-deployment.yaml**
   - Complete Kubernetes manifests
   - Deployment, Service, HPA, PDB
   - ConfigMaps and Secrets
   - Network policies
   - Ready to apply with `kubectl apply -f`

7. **Dockerfile**
   - Container image definition
   - Postfix configuration
   - Python policy daemon setup
   - Health checks

8. **relay_policy_daemon.py**
   - Rate limiting implementation
   - Domain validation
   - IP ACL enforcement
   - Prometheus metrics export
   - Postfix policy socket protocol

---

## 🎯 Quick Navigation by Role

### 👔 Executive / Manager
**Goal:** Understand what this does and why it matters

Read:
1. CEGP_Complete_Introduction.md (Executive Summary section)
2. CEGP_Architecture_Diagrams.md (High-level architecture)
3. CEGP_User_Defined_Mail_Servers.md (Compliance & References)

**Key Takeaways:**
- Relay container sits between CEGP and final destination
- Auto-scales 3-20 pods based on demand
- No message loss (local queue)
- Reduces load on CEGP cloud infrastructure
- Cost-effective alternative to CEGP resources

---

### 🛠️ Solutions Engineer / Technical Lead
**Goal:** Understand architecture and make deployment decisions

Read:
1. CEGP_Complete_Introduction.md (Architecture Overview + Key Features)
2. CEGP_User_Defined_Mail_Servers.md (Rate limits + Configuration)
3. LOAD_BALANCING_GUIDE.md (All load balancing options)
4. CEGP_Architecture_Diagrams.md (Message lifecycle)
5. kubernetes-deployment.yaml (Review manifest)

**Key Questions Answered:**
- How does rate limiting work? (Per CEGP specs)
- What load balancing options available? (5 strategies)
- How does auto-scaling work? (3-20 pods, CPU/memory driven)
- What's the deployment architecture? (Kubernetes native)
- How to integrate with CEGP? (User-defined mail servers model)

---

### 👨‍💻 DevOps / Platform Engineer
**Goal:** Deploy, operate, and maintain the system

Read:
1. CEGP_Quick_Reference.md (Deployment steps)
2. kubernetes-deployment.yaml (Apply manifest)
3. CEGP_Complete_Introduction.md (Monitoring & Management section)
4. LOAD_BALANCING_GUIDE.md (Monitoring & Tuning)
5. relay_policy_daemon.py (Understand rate limiting logic)

**Deployment Path:**
```
1. Review kubernetes-deployment.yaml
2. Follow CEGP_Quick_Reference.md Step 1-4
3. Configure CEGP console (Step 4)
4. Monitor with Prometheus/Grafana
5. Scale as needed (HPA automatic)
```

---

### 🔒 Security / Compliance Officer
**Goal:** Ensure security, audit trail, and compliance

Key Sections:
- **Security Considerations** (CEGP_User_Defined_Mail_Servers.md § 10)
  - Network isolation
  - Secret management (TLS certs)
  - RBAC access control
  
- **Compliance & Standards** (CEGP_User_Defined_Mail_Servers.md § 12)
  - RFC 5321 (SMTP)
  - GDPR compliance
  - Message audit trail
  - Structured logging (JSON format)

- **Troubleshooting** sections for security issues
  - Unauthorized connection attempts logged
  - IP whitelist enforcement
  - Domain whitelist validation

---

### 📊 Network/SRE
**Goal:** Ensure reliability, monitoring, and performance

Read:
1. LOAD_BALANCING_GUIDE.md (Complete guide to load balancing)
2. CEGP_Complete_Introduction.md (Monitoring & Management)
3. CEGP_Architecture_Diagrams.md (Load distribution examples)
4. CEGP_Quick_Reference.md (Troubleshooting section)

**Monitoring Setup:**
- Prometheus metrics on :9090/metrics
- Structured JSON logs to stdout
- Kubernetes health checks (liveness/readiness)
- HPA status and scaling events
- Pod anti-affinity for node distribution

---

## 📋 Document Details

### CEGP_Complete_Introduction.md
**Size:** ~15,000 words | **Read Time:** 45 min | **Level:** All

Complete beginner-friendly guide with:
- ASCII art diagrams of message flow
- 7-phase lifecycle breakdown
- Scaling scenario walkthroughs
- Common issues and solutions
- High-level to detailed explanations

**Best for:** First-time learning, demonstrations, presentations

---

### LOAD_BALANCING_GUIDE.md
**Size:** ~8,000 words | **Read Time:** 25 min | **Level:** Intermediate+

Comprehensive load balancing reference:
- 5 different load balancing strategies
- Kubernetes Service LB (default, recommended)
- Connection-level vs request-level balancing
- Multi-region failover with health checks
- HAProxy advanced configuration (optional)
- Real-world monitoring queries
- Troubleshooting imbalanced load

**Best for:** Network engineers, SREs, high-throughput deployments

---

### CEGP_User_Defined_Mail_Servers.md
**Size:** ~12,000 words | **Read Time:** 35 min | **Level:** Technical

Deep dive into CEGP integration:
- "User-Defined Mail Servers" relay model explained
- CEGP product specifications (rate limits, rules)
- Complete message flow with timelines
- Configuration management (hot-reload)
- Compliance and audit logging
- Troubleshooting CEGP-specific issues

**Best for:** Solutions architects, compliance teams, CEGP admins

---

### CEGP_Quick_Reference.md
**Size:** ~5,000 words | **Read Time:** 15 min | **Level:** Beginner

Fast setup and configuration guide:
- 4-step CEGP console setup
- 5-step relay container configuration
- Command-by-command examples
- Troubleshooting checklist
- Maintenance operations
- Summary of changes required

**Best for:** Quick deployment, hands-on setup, reference during operation

---

### CEGP_Architecture_Diagrams.md
**Size:** ~6,000 words | **Read Time:** 20 min | **Level:** Visual Learners

Visual reference with ASCII diagrams:
- High-level architecture
- Message state transitions
- Complete message journey (8 phases)
- Data flow between components
- CEGP console UI walkthrough
- Rate limiting visualization
- Pod failure & recovery scenarios

**Best for:** Visual learners, presentations, documentation review

---

### kubernetes-deployment.yaml
**Format:** YAML | **Complexity:** High | **Level:** Advanced

Production-ready Kubernetes manifests:
- Namespace creation
- ConfigMaps (postfix & relay policy)
- Secrets (TLS certificates)
- Deployment (3-20 pods, rolling update)
- Service (LoadBalancer type)
- HorizontalPodAutoscaler (CPU/memory driven)
- PodDisruptionBudget (min 2 replicas)
- NetworkPolicy (optional)
- ServiceMonitor (Prometheus integration)

**Use:** `kubectl apply -f kubernetes-deployment.yaml`

---

### Dockerfile
**Format:** Docker | **Complexity:** Medium | **Level:** Advanced

Container image definition:
- Base: Ubuntu 22.04
- Postfix SMTP server
- Python 3.10 policy daemon
- Redis in-memory cache
- Supervisor for multi-process management
- Health checks

**Use:** `docker build -t company/cegp-relay:1.0.0 .`

---

### relay_policy_daemon.py
**Format:** Python 3 | **Complexity:** Medium | **Lines:** ~600

Policy enforcement daemon:
- Rate limiting with Redis token bucket
- Domain and IP ACL validation
- CEGP IP whitelist enforcement
- Message size/recipient count validation
- Prometheus metrics export
- Structured JSON logging
- Postfix policy socket interface

**Key Classes:**
- `RelayConfig`: Configuration management (from env vars)
- `RateLimiter`: Token bucket algorithm (Redis backend)
- `CegpRelayPolicy`: Core business logic
- `PostfixPolicyService`: UNIX socket listener for Postfix

---

## 🚀 Deployment Checklist

### Pre-Deployment
- [ ] Review CEGP_Complete_Introduction.md
- [ ] Understand load balancing needs (LOAD_BALANCING_GUIDE.md)
- [ ] Kubernetes cluster available (1.20+)
- [ ] `kubectl` access to target cluster
- [ ] Docker registry credentials (if using private registry)

### Deployment
- [ ] Build Docker image: `docker build -t company/relay:1.0 .`
- [ ] Push to registry: `docker push company/relay:1.0`
- [ ] Update image tag in kubernetes-deployment.yaml
- [ ] Deploy: `kubectl apply -f kubernetes-deployment.yaml`
- [ ] Verify pods running: `kubectl get pods -n email-security`
- [ ] Get LoadBalancer IP: `kubectl get svc -n email-security`

### Configuration
- [ ] Configure relay domains: `kubectl patch configmap relay-policy ...`
- [ ] Configure CEGP IPs: `kubectl patch configmap relay-policy ...`
- [ ] Configure CEGP console (User-Defined Mail Servers)
- [ ] Add relay IP/FQDN to CEGP
- [ ] Send test message from CEGP console
- [ ] Verify message arrives

### Verification
- [ ] Check pod logs: `kubectl logs -l app=cegp-smtp-relay`
- [ ] View metrics: `kubectl port-forward svc/cegp-smtp-relay 9090:9090`
- [ ] Monitor HPA: `kubectl get hpa -n email-security -w`
- [ ] Load test (send messages through CEGP)
- [ ] Verify scaling (CPU > 70% should trigger scale-up)

### Operations
- [ ] Set up Prometheus scraping (:9090/metrics)
- [ ] Create Grafana dashboards
- [ ] Configure alerts (rate limit hits, queue buildup)
- [ ] Document runbooks for common issues
- [ ] Train team on operations

---

## 🔍 Finding Specific Information

### "How do I..."

| Question | Document | Section |
|----------|----------|---------|
| Deploy the relay? | CEGP_Quick_Reference | Steps 1-2 |
| Configure CEGP console? | CEGP_Quick_Reference | Steps 3-4 |
| Add a domain to the relay? | CEGP_Complete_Introduction | Troubleshooting: "Domain not in relay list" |
| Scale up manually? | CEGP_Complete_Introduction | Monitoring & Management |
| Change load balancing strategy? | LOAD_BALANCING_GUIDE | All sections |
| Understand rate limiting? | CEGP_User_Defined_Mail_Servers | Section 4 |
| Monitor the relay? | CEGP_Complete_Introduction | Monitoring & Management |
| Troubleshoot "Connection refused"? | CEGP_Quick_Reference | Troubleshooting |
| Set up multi-region? | LOAD_BALANCING_GUIDE | Multi-Region Load Balancing |
| Use HAProxy instead of K8s LB? | LOAD_BALANCING_GUIDE | HAProxy Configuration |
| Understand the message flow? | CEGP_Complete_Introduction | How It Works - Step by Step |
| See the architecture? | CEGP_Architecture_Diagrams | All sections |

---

## 📞 Support & Resources

### Documentation References
- **Trend Micro CEGP API:** https://docs.trendmicro.com/en-us/documentation/article/email-security-v1ecs-rest-api-online-help-getting-started-with
- **Postfix Manual:** http://www.postfix.org/
- **Kubernetes Docs:** https://kubernetes.io/docs/
- **RFC 5321 (SMTP):** https://tools.ietf.org/html/rfc5321

### Troubleshooting Path

```
Problem Occurs
        ↓
Check CEGP console logs
        ↓
Check relay pod logs: kubectl logs -l app=cegp-smtp-relay
        ↓
Check metrics: kubectl port-forward :9090
        ↓
Match error to one of these docs:
  - CEGP_Quick_Reference.md § Troubleshooting
  - CEGP_Complete_Introduction.md § Troubleshooting
  - LOAD_BALANCING_GUIDE.md § Troubleshooting Load Balancing
        ↓
Follow resolution steps
        ↓
Monitor for recurrence
```

---

## 📊 Solution Statistics

```
Total Documentation:     ~50,000 words
Total Code:               ~1,000 lines
Diagrams & Examples:      30+ ASCII diagrams
Configuration Examples:   15+ YAML/config snippets
Troubleshooting Guides:   25+ scenarios covered
Load Balancing Options:   5+ strategies explained
Test Scenarios:           10+ examples with timelines
```

---

## 🎓 Learning Path (Recommended)

### Day 1: Understand
- Read: CEGP_Complete_Introduction.md (1 hour)
- Review: CEGP_Architecture_Diagrams.md (30 min)
- Understand: Message flow, scaling, features

### Day 2: Plan
- Read: CEGP_User_Defined_Mail_Servers.md (45 min)
- Read: LOAD_BALANCING_GUIDE.md (30 min)
- Make decisions: Load balancing strategy, scaling params

### Day 3: Deploy
- Follow: CEGP_Quick_Reference.md § Deployment (30 min)
- Deploy: kubernetes-deployment.yaml
- Configure: CEGP console
- Test: Send test messages

### Day 4: Monitor & Tune
- Set up: Prometheus/Grafana dashboards
- Monitor: Metrics, scaling events, queue
- Tune: HPA thresholds, rate limits if needed
- Load test: Verify auto-scaling

### Ongoing: Operations
- Use: CEGP_Quick_Reference.md for common tasks
- Refer: CEGP_Complete_Introduction.md § Troubleshooting
- Monitor: Relay container health and performance

---

## 📝 Version History

```
Version 3.0 - Current
  ✓ Complete introduction guide with examples
  ✓ Load balancing comprehensive guide
  ✓ Kubernetes deployment manifests
  ✓ Policy daemon with rate limiting
  ✓ Multi-region support documentation
  ✓ Complete troubleshooting guides
  
Version 2.0 - Earlier
  ✓ CEGP user-defined mail servers model
  ✓ Architecture diagrams
  ✓ Quick reference guide
  
Version 1.0 - Original
  ✓ Product specification
  ✓ Deployment guide
```

---

## 🎯 Success Criteria

After reading this documentation, you should be able to:

✓ Explain what the relay container does in simple terms  
✓ Draw the architecture from memory  
✓ Deploy it to Kubernetes in < 30 minutes  
✓ Configure CEGP console correctly  
✓ Monitor relay health with Prometheus  
✓ Understand auto-scaling behavior  
✓ Troubleshoot common issues  
✓ Explain load balancing options to others  
✓ Implement multi-region failover  
✓ Optimize rate limits for your workload  

---

## 📄 License & Support

This solution package is provided as a reference implementation for Trend Micro CEGP integration.

**Support:** Refer to Trend Micro support for CEGP-specific issues: https://success.trendmicro.com

---

**Package Version:** 3.0 (Complete with Introduction & Load Balancing)  
**Last Updated:** March 2025  
**Status:** Production Ready  
**Complexity:** Intermediate to Advanced  
**Estimated Deployment Time:** 2-4 hours  
**Estimated Learning Time:** 4-8 hours  

---

**Ready to start?** → Begin with **CEGP_Complete_Introduction.md** 🚀
