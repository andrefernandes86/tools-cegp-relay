#!/bin/bash
# CEGP SMTP Relay Installation and Management Script
# Version: 1.0
# Description: Complete deployment and management solution for CEGP SMTP Relay

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration file
CONFIG_FILE="./config/deployment.conf"
TEMP_CONFIG="/tmp/cegp-config.tmp"

# Function to print colored output
print_header() {
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}========================================${NC}"
}

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

print_question() {
    echo -e "${CYAN}[QUESTION]${NC} $1"
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Function to validate CIDR
validate_cidr() {
    local cidr=$1
    if [[ $cidr =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        local ip=$(echo $cidr | cut -d'/' -f1)
        local mask=$(echo $cidr | cut -d'/' -f2)
        if validate_ip "$ip" && [[ $mask -ge 0 && $mask -le 32 ]]; then
            return 0
        fi
    fi
    return 1
}

# Function to validate domain
validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    fi
    return 1
}

# Function to create configuration directory
create_config_dir() {
    mkdir -p ./config
    mkdir -p ./logs
    mkdir -p ./scripts
}

# Function to save configuration
save_config() {
    cat > "$CONFIG_FILE" << EOF
# CEGP SMTP Relay Configuration
# Generated on: $(date)

DEPLOYMENT_TYPE="$DEPLOYMENT_TYPE"
CLUSTER_TYPE="$CLUSTER_TYPE"
MIN_REPLICAS="$MIN_REPLICAS"
MAX_REPLICAS="$MAX_REPLICAS"
REMOTE_SERVER="$REMOTE_SERVER"
REMOTE_USER="$REMOTE_USER"
REMOTE_PASSWORD="$REMOTE_PASSWORD"
CEGP_HOST="$CEGP_HOST"
CEGP_PORT="$CEGP_PORT"
AUTHORIZED_DOMAINS="$AUTHORIZED_DOMAINS"
AUTHORIZED_IPS="$AUTHORIZED_IPS"
RATE_LIMIT_IP_PER_MIN="$RATE_LIMIT_IP_PER_MIN"
RATE_LIMIT_RCPT_PER_MIN="$RATE_LIMIT_RCPT_PER_MIN"
NAMESPACE="$NAMESPACE"
EOF
    print_success "Configuration saved to $CONFIG_FILE"
}

# Function to load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# Function to get deployment type
get_deployment_type() {
    print_header "DEPLOYMENT CONFIGURATION"
    
    while true; do
        print_question "Where do you want to deploy the CEGP SMTP Relay?"
        echo "1) Local Kubernetes cluster (current machine)"
        echo "2) Remote Kubernetes cluster"
        echo "3) Exit"
        read -p "Enter your choice (1-3): " choice
        
        case $choice in
            1)
                DEPLOYMENT_TYPE="local"
                get_local_config
                break
                ;;
            2)
                DEPLOYMENT_TYPE="remote"
                get_remote_config
                break
                ;;
            3)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please select 1, 2, or 3."
                ;;
        esac
    done
}

# Function to get local deployment configuration
get_local_config() {
    print_header "LOCAL DEPLOYMENT CONFIGURATION"
    
    while true; do
        read -p "Minimum number of relay nodes (2-20, default: 3): " min_nodes
        min_nodes=${min_nodes:-3}
        if [[ $min_nodes -ge 2 && $min_nodes -le 20 ]]; then
            MIN_REPLICAS=$min_nodes
            break
        else
            print_error "Please enter a number between 2 and 20"
        fi
    done
    
    while true; do
        read -p "Maximum number of relay nodes ($MIN_REPLICAS-20, default: 20): " max_nodes
        max_nodes=${max_nodes:-20}
        if [[ $max_nodes -ge $MIN_REPLICAS && $max_nodes -le 20 ]]; then
            MAX_REPLICAS=$max_nodes
            break
        else
            print_error "Please enter a number between $MIN_REPLICAS and 20"
        fi
    done
    
    CLUSTER_TYPE="local"
}

# Function to get remote deployment configuration
get_remote_config() {
    print_header "REMOTE DEPLOYMENT CONFIGURATION"
    
    while true; do
        read -p "Remote server IP address: " server_ip
        if validate_ip "$server_ip"; then
            REMOTE_SERVER=$server_ip
            break
        else
            print_error "Invalid IP address format"
        fi
    done
    
    read -p "Remote server username: " remote_user
    REMOTE_USER=$remote_user
    
    read -s -p "Remote server password: " remote_password
    echo
    REMOTE_PASSWORD=$remote_password
    
    while true; do
        read -p "Minimum number of relay nodes (2-20, default: 3): " min_nodes
        min_nodes=${min_nodes:-3}
        if [[ $min_nodes -ge 2 && $min_nodes -le 20 ]]; then
            MIN_REPLICAS=$min_nodes
            break
        else
            print_error "Please enter a number between 2 and 20"
        fi
    done
    
    while true; do
        read -p "Maximum number of relay nodes ($MIN_REPLICAS-20, default: 20): " max_nodes
        max_nodes=${max_nodes:-20}
        if [[ $max_nodes -ge $MIN_REPLICAS && $max_nodes -le 20 ]]; then
            MAX_REPLICAS=$max_nodes
            break
        else
            print_error "Please enter a number between $MIN_REPLICAS and 20"
        fi
    done
    
    CLUSTER_TYPE="remote"
}

# Current manifest uses a single PVC with ReadWriteOnce (RWO).
# That allows only one active writer pod for the queue volume.
enforce_storage_scaling_constraints() {
    if [[ "${MIN_REPLICAS:-1}" -gt 1 || "${MAX_REPLICAS:-1}" -gt 1 ]]; then
        print_warning "Current storage mode is single-queue PVC (ReadWriteOnce)."
        print_warning "Scaling above 1 replica is not supported with this manifest."
        print_warning "For now, forcing replicas to 1/1 to ensure reliable deployment."
        MIN_REPLICAS=1
        MAX_REPLICAS=1
    fi
}

# Function to get CEGP configuration
get_cegp_config() {
    print_header "CEGP CLOUD EMAIL GATEWAY CONFIGURATION"
    
    print_status "Select CEGP Gateway configuration:"
    echo "1) Custom Trend Micro tenant (e.g., company-onmicrosoft-com.relay.tmes.trendmicro.com)"
    echo "2) Custom hostname"
    
    read -p "Enter your choice (1-2, default: 1): " cegp_choice
    cegp_choice=${cegp_choice:-1}
    
    case $cegp_choice in
        1)
            read -p "Enter your tenant prefix (e.g., 'company-onmicrosoft-com'): " tenant_prefix
            if [[ -n "$tenant_prefix" ]]; then
                # Check if user already provided full hostname
                if [[ "$tenant_prefix" == *.relay.tmes.trendmicro.com ]]; then
                    CEGP_HOST="$tenant_prefix"
                else
                    CEGP_HOST="${tenant_prefix}.relay.tmes.trendmicro.com"
                fi
            else
                print_error "Tenant prefix is required"
                get_cegp_config
                return
            fi
            ;;
        2)
            read -p "Enter custom CEGP hostname: " custom_host
            if [[ -n "$custom_host" ]]; then
                CEGP_HOST="$custom_host"
            else
                print_error "Custom hostname is required"
                get_cegp_config
                return
            fi
            ;;
        *)
            print_warning "Invalid choice, using tenant configuration"
            get_cegp_config
            return
            ;;
    esac
    
    read -p "CEGP Gateway port (default: 25): " cegp_port
    CEGP_PORT=${cegp_port:-25}
    
    # Validate port
    if ! [[ "$CEGP_PORT" =~ ^[0-9]+$ ]] || [[ $CEGP_PORT -lt 1 || $CEGP_PORT -gt 65535 ]]; then
        print_warning "Invalid port, using default 25"
        CEGP_PORT=25
    fi
    
    print_success "CEGP Gateway: $CEGP_HOST:$CEGP_PORT"
}

# Function to get authorized domains
get_authorized_domains() {
    print_header "AUTHORIZED EMAIL DOMAINS"
    print_status "Configure email domains that are allowed to send through this relay"
    
    echo "1) Add domains manually"
    echo "2) Allow all domains (not recommended for production)"
    
    read -p "Enter your choice (1-2, default: 1): " domain_choice
    domain_choice=${domain_choice:-1}
    
    case $domain_choice in
        1)
            print_status "Enter domains one by one. Examples: company.com, subsidiary.org, branch.local"
            AUTHORIZED_DOMAINS=""
            while true; do
                read -p "Enter domain (or 'done' to finish): " domain
                if [[ "$domain" == "done" ]]; then
                    break
                elif [[ -z "$domain" ]]; then
                    print_error "Please enter a domain or 'done' to finish"
                elif validate_domain "$domain"; then
                    if [[ -z "$AUTHORIZED_DOMAINS" ]]; then
                        AUTHORIZED_DOMAINS="$domain"
                    else
                        AUTHORIZED_DOMAINS="$AUTHORIZED_DOMAINS,$domain"
                    fi
                    print_success "Added domain: $domain"
                else
                    print_error "Invalid domain format: $domain"
                fi
            done
            ;;
        2)
            print_warning "Allowing all domains (not recommended for production)"
            AUTHORIZED_DOMAINS=""
            ;;
        *)
            print_warning "Invalid choice, using manual entry"
            get_authorized_domains
            return
            ;;
    esac
    
    if [[ -z "$AUTHORIZED_DOMAINS" ]]; then
        print_warning "No domain restrictions configured. All domains will be allowed."
    fi
}

# Function to get authorized IP addresses
get_authorized_ips() {
    print_header "AUTHORIZED IP ADDRESSES"
    print_status "Configure IP addresses/networks that are allowed to send through this relay"
    
    echo "1) Add IP ranges manually"
    echo "2) Common private networks (192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12)"
    echo "3) Kubernetes cluster only (10.0.0.0/8, 172.16.0.0/12)"
    echo "4) Local network only (192.168.0.0/16)"
    echo "5) Allow all IPs (not recommended for production)"
    
    read -p "Enter your choice (1-5, default: 2): " ip_choice
    ip_choice=${ip_choice:-2}
    
    case $ip_choice in
        1)
            print_status "Enter IP addresses/networks in CIDR notation"
            print_status "Examples: 192.168.1.0/24, 10.0.0.0/8, 172.16.5.10/32"
            AUTHORIZED_IPS=""
            while true; do
                read -p "Enter IP/CIDR (or 'done' to finish): " ip_cidr
                if [[ "$ip_cidr" == "done" ]]; then
                    break
                elif [[ -z "$ip_cidr" ]]; then
                    print_error "Please enter an IP/CIDR or 'done' to finish"
                elif validate_cidr "$ip_cidr" || validate_ip "$ip_cidr"; then
                    if [[ -z "$AUTHORIZED_IPS" ]]; then
                        AUTHORIZED_IPS="$ip_cidr"
                    else
                        AUTHORIZED_IPS="$AUTHORIZED_IPS,$ip_cidr"
                    fi
                    print_success "Added IP/network: $ip_cidr"
                else
                    print_error "Invalid IP/CIDR format: $ip_cidr"
                fi
            done
            ;;
        2)
            print_status "Using common private networks..."
            AUTHORIZED_IPS="192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
            print_success "Added networks: $AUTHORIZED_IPS"
            ;;
        3)
            print_status "Using Kubernetes cluster networks..."
            AUTHORIZED_IPS="10.0.0.0/8,172.16.0.0/12"
            print_success "Added networks: $AUTHORIZED_IPS"
            ;;
        4)
            print_status "Using local network only..."
            AUTHORIZED_IPS="192.168.0.0/16"
            print_success "Added network: $AUTHORIZED_IPS"
            ;;
        5)
            print_warning "Allowing all IPs (not recommended for production)"
            AUTHORIZED_IPS=""
            ;;
        *)
            print_warning "Invalid choice, using common private networks"
            AUTHORIZED_IPS="192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
            ;;
    esac
    
    if [[ -z "$AUTHORIZED_IPS" ]]; then
        print_warning "No IP restrictions configured. All IPs will be allowed."
    fi
}

# Function to get rate limiting configuration
get_rate_limits() {
    print_header "RATE LIMITING CONFIGURATION"
    
    read -p "Rate limit per IP per minute (default: 2000): " rate_ip
    RATE_LIMIT_IP_PER_MIN=${rate_ip:-2000}
    
    read -p "Rate limit per recipient per minute (default: 200): " rate_rcpt
    RATE_LIMIT_RCPT_PER_MIN=${rate_rcpt:-200}
}

# Function to setup kubectl for remote
setup_remote_kubectl() {
    print_status "Setting up remote kubectl access..."
    
    # Create SSH key if not exists
    if [[ ! -f ~/.ssh/id_rsa ]]; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    fi
    
    # Copy SSH key to remote server
    sshpass -p "$REMOTE_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_SERVER" || true
    
    # Test SSH connection
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_SERVER" "echo 'SSH connection successful'"; then
        print_success "SSH connection established"
    else
        print_error "Failed to establish SSH connection"
        return 1
    fi
}

# Function to execute kubectl commands
execute_kubectl() {
    local cmd="$1"
    if [[ "$DEPLOYMENT_TYPE" == "local" ]]; then
        eval "$cmd"
    else
        ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_SERVER" "$cmd"
    fi
}

# Function to deploy the application
deploy_application() {
    print_header "DEPLOYING CEGP SMTP RELAY"
    
    # Create namespace
    NAMESPACE="email-security"

    # Prevent impossible scale targets for current PVC model.
    enforce_storage_scaling_constraints
    
    # Update deployment files with configuration
    update_deployment_files
    
    print_status "Installing local-path provisioner..."
    execute_kubectl "k0s kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml"
    
    print_status "Validating generated manifest..."
    if [[ "$DEPLOYMENT_TYPE" == "remote" ]]; then
        # Copy deployment files to remote server for validation and apply
        scp -r kubernetes/ "$REMOTE_USER@$REMOTE_SERVER:~/cegp-relay-deploy/"
        execute_kubectl "k0s kubectl apply --dry-run=client -f ~/cegp-relay-deploy/kubernetes-deployment-configured.yaml >/dev/null"
    else
        execute_kubectl "k0s kubectl apply --dry-run=client -f kubernetes/kubernetes-deployment-configured.yaml >/dev/null"
    fi

    print_status "Deploying CEGP SMTP Relay..."
    if [[ "$DEPLOYMENT_TYPE" == "remote" ]]; then
        execute_kubectl "k0s kubectl apply -f ~/cegp-relay-deploy/kubernetes-deployment-configured.yaml"
    else
        execute_kubectl "k0s kubectl apply -f kubernetes/kubernetes-deployment-configured.yaml"
    fi
    
    # Immediately clean stale pods/ReplicaSets from previous revisions to avoid false failures.
    cleanup_stale_pods

    print_status "Waiting for deployment to be ready..."
    sleep 10
    
    # Check deployment status
    if check_deployment_status; then
        cleanup_stale_pods
        print_success "CEGP SMTP Relay deployed successfully!"
        show_deployment_info
    else
        print_error "Deployment failed or is not ready"
        show_troubleshooting_info
    fi
}

# Function to update deployment files with user configuration
update_deployment_files() {
    print_status "Updating deployment configuration..."
    
    # Create temporary deployment file
    cp kubernetes/kubernetes-deployment-simple.yaml "$TEMP_CONFIG"
    
    # Use a more robust approach with temporary files and simple replacements
    # Update replicas
    awk -v min="$MIN_REPLICAS" -v max="$MAX_REPLICAS" '
        /replicas: 3/ { gsub(/3/, min) }
        /minReplicas: 3/ { gsub(/3/, min) }
        /maxReplicas: 20/ { gsub(/20/, max) }
        { print }
    ' "$TEMP_CONFIG" > "${TEMP_CONFIG}.tmp" && mv "${TEMP_CONFIG}.tmp" "$TEMP_CONFIG"
    
    # Update CEGP configuration
    awk -v host="$CEGP_HOST" -v port="$CEGP_PORT" '
        /RELAYHOST/ { gsub(/relay\.mx\.trendmicro\.com:25/, host ":" port) }
        /relay\.mx\.trendmicro\.com/ { gsub(/relay\.mx\.trendmicro\.com/, host) }
        { print }
    ' "$TEMP_CONFIG" > "${TEMP_CONFIG}.tmp" && mv "${TEMP_CONFIG}.tmp" "$TEMP_CONFIG"
    
    # Update domains and IPs in environment variables
    awk -v domains="$AUTHORIZED_DOMAINS" -v ips="$AUTHORIZED_IPS" '
        /ALLOWED_SENDER_DOMAINS/ { 
            if (domains != "") {
                gsub(/value: "[^"]*"/, "value: \"" domains "\"") 
            }
        }
        /POSTFIX_relay_domains/ { 
            if (domains != "") {
                gsub(/value: "[^"]*"/, "value: \"" domains "\"") 
            }
        }
        /MYNETWORKS/ { 
            base_networks = "127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"
            if (ips != "") {
                # Replace commas with spaces in IP list
                gsub(/,/, " ", ips)
                gsub(/value: "[^"]*"/, "value: \"" base_networks " " ips "\"")
            } else {
                gsub(/value: "[^"]*"/, "value: \"" base_networks "\"")
            }
        }
        { print }
    ' "$TEMP_CONFIG" > "${TEMP_CONFIG}.tmp" && mv "${TEMP_CONFIG}.tmp" "$TEMP_CONFIG"
    
    # Copy back the updated file
    cp "$TEMP_CONFIG" kubernetes/kubernetes-deployment-configured.yaml
}

# Function to check deployment status
check_deployment_status() {
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        # Read current deployment and pod health.
        local ready_pods available_replicas failed_pods
        ready_pods=$(execute_kubectl "k0s kubectl get pods -n $NAMESPACE -l app=cegp-smtp-relay --no-headers 2>/dev/null | awk '\$2 ~ /^1\\/1$/ && \$3 == \"Running\" {count++} END {print count+0}'" || echo "0")
        available_replicas=$(execute_kubectl "k0s kubectl get deploy cegp-smtp-relay -n $NAMESPACE -o jsonpath='{.status.availableReplicas}' 2>/dev/null" || echo "")
        failed_pods=$(execute_kubectl "k0s kubectl get pods -n $NAMESPACE -l app=cegp-smtp-relay --no-headers 2>/dev/null | awk '\$3 ~ /CrashLoopBackOff|Error|ImagePullBackOff|CreateContainerError|RunContainerError|Failed/ {count++} END {print count+0}'" || echo "0")

        # Normalize empty availableReplicas to 0.
        if [[ -z "$available_replicas" ]]; then
            available_replicas=0
        fi

        # Success condition: real service health achieved, even if rollout metadata lags.
        if [[ $ready_pods -ge $MIN_REPLICAS && $available_replicas -ge $MIN_REPLICAS ]]; then
            return 0
        fi

        # Self-heal stale failed pods during wait to avoid indefinite convergence stalls.
        if [[ $failed_pods -gt 0 ]]; then
            cleanup_stale_pods >/dev/null 2>&1 || true
        fi

        print_status "Waiting for rollout and ready pods... ($((attempt + 1))/$max_attempts) [ready=$ready_pods available=$available_replicas failed=$failed_pods target=$MIN_REPLICAS]"
        sleep 10
        ((attempt++))
    done
    
    return 1
}

# Function to clean up stale pods from old ReplicaSets
cleanup_stale_pods() {
    print_status "Cleaning up stale pods from old ReplicaSets..."

    # Scale old ReplicaSets to zero, keep only newest one
    execute_kubectl "k0s kubectl get rs -n $NAMESPACE -l app=cegp-smtp-relay --sort-by=.metadata.creationTimestamp -o name | head -n -1 | xargs -r -I{} k0s kubectl scale -n $NAMESPACE {} --replicas=0" || true

    # Delete failed old pods if any remain
    execute_kubectl "k0s kubectl get pods -n $NAMESPACE -l app=cegp-smtp-relay --no-headers 2>/dev/null | awk '\$3 ~ /CrashLoopBackOff|Error|ImagePullBackOff|Failed/ {print \$1}' | xargs -r -I{} k0s kubectl delete pod -n $NAMESPACE {} --ignore-not-found=true" || true
}

# Function to show deployment information
show_deployment_info() {
    print_header "DEPLOYMENT INFORMATION"
    
    # Get service information
    local service_info=$(execute_kubectl "k0s kubectl get svc cegp-smtp-relay -n $NAMESPACE -o wide 2>/dev/null" || echo "Service not found")
    echo "$service_info"
    
    # Get LoadBalancer IP
    local lb_ip=$(execute_kubectl "k0s kubectl get svc cegp-smtp-relay -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null" || echo "")
    
    if [[ -n "$lb_ip" && "$lb_ip" != "null" ]]; then
        print_success "SMTP Relay is accessible at: $lb_ip:25"
        echo "Configure your applications to use: $lb_ip:25"
        echo "Add to CEGP console: $lb_ip:25"
    else
        print_warning "LoadBalancer IP not yet assigned. Use NodePort or check later."
    fi
    
    # Show pod status
    echo
    print_status "Pod Status:"
    execute_kubectl "k0s kubectl get pods -n $NAMESPACE -l app=cegp-smtp-relay"
}

# Function to show troubleshooting information
show_troubleshooting_info() {
    print_header "TROUBLESHOOTING INFORMATION"
    
    print_status "Pod Status:"
    execute_kubectl "k0s kubectl get pods -n $NAMESPACE -l app=cegp-smtp-relay"

    print_status "ReplicaSets:"
    execute_kubectl "k0s kubectl get rs -n $NAMESPACE -l app=cegp-smtp-relay --sort-by=.metadata.creationTimestamp"
    
    print_status "Recent Events:"
    execute_kubectl "k0s kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10"
    
    print_status "Newest Pod Logs (last 40 lines):"
    execute_kubectl "k0s kubectl logs -n $NAMESPACE \$(k0s kubectl get pods -n $NAMESPACE -l app=cegp-smtp-relay --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}') --tail=40"
}

# Function to show status
show_status() {
    print_header "CEGP SMTP RELAY STATUS"
    
    if ! load_config; then
        print_error "No configuration found. Please run installation first."
        return 1
    fi
    
    # Show deployment status
    print_status "Deployment Type: $DEPLOYMENT_TYPE ($CLUSTER_TYPE)"
    print_status "Namespace: $NAMESPACE"
    
    # Show pod status
    echo
    print_status "Pod Status:"
    execute_kubectl "k0s kubectl get pods -n $NAMESPACE -l app=cegp-smtp-relay -o wide"
    
    # Show HPA status
    echo
    print_status "Auto-scaling Status:"
    execute_kubectl "k0s kubectl get hpa -n $NAMESPACE"
    
    # Show service status
    echo
    print_status "Service Status:"
    execute_kubectl "k0s kubectl get svc cegp-smtp-relay -n $NAMESPACE"
    
    # Show resource usage
    echo
    print_status "Resource Usage:"
    execute_kubectl "k0s kubectl top pods -n $NAMESPACE -l app=cegp-smtp-relay" || print_warning "Metrics not available"
    
    # Show recent logs
    echo
    print_status "Recent Activity (last 10 lines):"
    execute_kubectl "k0s kubectl logs -l app=cegp-smtp-relay -n $NAMESPACE --tail=10 --since=5m"
}

# Function to monitor real-time metrics
monitor_realtime() {
    print_header "REAL-TIME MONITORING"
    
    if ! load_config; then
        print_error "No configuration found. Please run installation first."
        return 1
    fi
    
    print_status "Starting real-time monitoring... Press Ctrl+C to stop"
    print_status "Monitoring namespace: $NAMESPACE"
    
    while true; do
        clear
        echo -e "${PURPLE}CEGP SMTP Relay - Real-time Monitoring${NC}"
        echo -e "${PURPLE}$(date)${NC}"
        echo "========================================"
        
        # Pod status
        echo -e "${BLUE}Active Nodes:${NC}"
        local running_pods=$(execute_kubectl "k0s kubectl get pods -n $NAMESPACE -l app=cegp-smtp-relay --no-headers 2>/dev/null | grep Running | wc -l" || echo "0")
        local total_pods=$(execute_kubectl "k0s kubectl get pods -n $NAMESPACE -l app=cegp-smtp-relay --no-headers 2>/dev/null | wc -l" || echo "0")
        echo "Running: $running_pods / Total: $total_pods"
        
        # Resource usage
        echo
        echo -e "${BLUE}Resource Usage:${NC}"
        execute_kubectl "k0s kubectl top pods -n $NAMESPACE -l app=cegp-smtp-relay --no-headers 2>/dev/null | head -5" || echo "Metrics not available"
        
        # Message statistics (from logs)
        echo
        echo -e "${BLUE}Message Statistics (last 60 seconds):${NC}"
        local recent_logs=$(execute_kubectl "k0s kubectl logs -l app=cegp-smtp-relay -n $NAMESPACE --since=60s 2>/dev/null" || echo "")
        
        local received_count=$(echo "$recent_logs" | grep -c "status=sent\|MAIL FROM" 2>/dev/null || echo "0")
        local delivered_count=$(echo "$recent_logs" | grep -c "status=sent" 2>/dev/null || echo "0")
        
        echo "Messages received: $received_count"
        echo "Messages delivered: $delivered_count"
        
        # Queue status
        echo
        echo -e "${BLUE}Queue Status:${NC}"
        local queue_size=$(execute_kubectl "k0s kubectl exec -it deployment/cegp-smtp-relay -n $NAMESPACE -- postqueue -p 2>/dev/null | grep -c '^[A-F0-9]' 2>/dev/null" || echo "0")
        echo "Messages in queue: $queue_size"
        
        # Auto-scaling info
        echo
        echo -e "${BLUE}Auto-scaling:${NC}"
        execute_kubectl "k0s kubectl get hpa cegp-smtp-relay-hpa -n $NAMESPACE --no-headers 2>/dev/null" || echo "HPA not available"
        
        sleep 5
    done
}

# Function to manage configuration
manage_configuration() {
    while true; do
        print_header "CONFIGURATION MANAGEMENT"
        
        if load_config; then
            echo "Current Configuration:"
            echo "- Deployment: $DEPLOYMENT_TYPE ($CLUSTER_TYPE)"
            echo "- CEGP Host: $CEGP_HOST:$CEGP_PORT"
            echo "- Replicas: $MIN_REPLICAS - $MAX_REPLICAS"
            echo "- Domains: $AUTHORIZED_DOMAINS"
            echo "- IPs: $AUTHORIZED_IPS"
        else
            print_warning "No configuration found"
        fi
        
        echo
        echo "1) Add/Remove authorized domains"
        echo "2) Add/Remove authorized IP addresses"
        echo "3) Update CEGP gateway settings"
        echo "4) Update scaling settings"
        echo "5) Update rate limiting"
        echo "6) Apply configuration changes"
        echo "7) Back to main menu"
        
        read -p "Enter your choice (1-7): " choice
        
        case $choice in
            1) manage_domains ;;
            2) manage_ips ;;
            3) update_cegp_settings ;;
            4) update_scaling_settings ;;
            5) update_rate_limits ;;
            6) apply_configuration_changes ;;
            7) break ;;
            *) print_error "Invalid choice" ;;
        esac
    done
}

# Function to manage domains
manage_domains() {
    print_header "MANAGE AUTHORIZED DOMAINS"
    
    if [[ -n "$AUTHORIZED_DOMAINS" ]]; then
        echo "Current domains:"
        IFS=',' read -ra DOMAINS <<< "$AUTHORIZED_DOMAINS"
        for i in "${!DOMAINS[@]}"; do
            echo "$((i+1))) ${DOMAINS[$i]}"
        done
    else
        echo "No domains configured"
    fi
    
    echo
    echo "1) Add domain"
    echo "2) Remove domain"
    echo "3) Back"
    
    read -p "Enter your choice (1-3): " choice
    
    case $choice in
        1)
            read -p "Enter domain to add: " new_domain
            if validate_domain "$new_domain"; then
                if [[ -z "$AUTHORIZED_DOMAINS" ]]; then
                    AUTHORIZED_DOMAINS="$new_domain"
                else
                    AUTHORIZED_DOMAINS="$AUTHORIZED_DOMAINS,$new_domain"
                fi
                print_success "Domain added: $new_domain"
            else
                print_error "Invalid domain format"
            fi
            ;;
        2)
            if [[ -n "$AUTHORIZED_DOMAINS" ]]; then
                read -p "Enter domain number to remove: " domain_num
                IFS=',' read -ra DOMAINS <<< "$AUTHORIZED_DOMAINS"
                if [[ $domain_num -ge 1 && $domain_num -le ${#DOMAINS[@]} ]]; then
                    unset "DOMAINS[$((domain_num-1))]"
                    AUTHORIZED_DOMAINS=$(IFS=','; echo "${DOMAINS[*]}")
                    print_success "Domain removed"
                else
                    print_error "Invalid domain number"
                fi
            else
                print_warning "No domains to remove"
            fi
            ;;
    esac
}

# Function to manage IPs
manage_ips() {
    print_header "MANAGE AUTHORIZED IP ADDRESSES"
    
    if [[ -n "$AUTHORIZED_IPS" ]]; then
        echo "Current IP addresses/networks:"
        IFS=',' read -ra IPS <<< "$AUTHORIZED_IPS"
        for i in "${!IPS[@]}"; do
            echo "$((i+1))) ${IPS[$i]}"
        done
    else
        echo "No IP restrictions configured"
    fi
    
    echo
    echo "1) Add IP/network"
    echo "2) Remove IP/network"
    echo "3) Back"
    
    read -p "Enter your choice (1-3): " choice
    
    case $choice in
        1)
            read -p "Enter IP/CIDR to add: " new_ip
            if validate_cidr "$new_ip" || validate_ip "$new_ip"; then
                if [[ -z "$AUTHORIZED_IPS" ]]; then
                    AUTHORIZED_IPS="$new_ip"
                else
                    AUTHORIZED_IPS="$AUTHORIZED_IPS,$new_ip"
                fi
                print_success "IP/network added: $new_ip"
            else
                print_error "Invalid IP/CIDR format"
            fi
            ;;
        2)
            if [[ -n "$AUTHORIZED_IPS" ]]; then
                read -p "Enter IP number to remove: " ip_num
                IFS=',' read -ra IPS <<< "$AUTHORIZED_IPS"
                if [[ $ip_num -ge 1 && $ip_num -le ${#IPS[@]} ]]; then
                    unset "IPS[$((ip_num-1))]"
                    AUTHORIZED_IPS=$(IFS=','; echo "${IPS[*]}")
                    print_success "IP/network removed"
                else
                    print_error "Invalid IP number"
                fi
            else
                print_warning "No IPs to remove"
            fi
            ;;
    esac
}

# Function to update CEGP settings
update_cegp_settings() {
    print_header "UPDATE CEGP GATEWAY SETTINGS"
    
    echo "Current CEGP settings:"
    echo "Host: $CEGP_HOST"
    echo "Port: $CEGP_PORT"
    
    read -p "Enter new CEGP hostname (or press Enter to keep current): " new_host
    if [[ -n "$new_host" ]]; then
        CEGP_HOST="$new_host"
    fi
    
    read -p "Enter new CEGP port (or press Enter to keep current): " new_port
    if [[ -n "$new_port" ]]; then
        if [[ "$new_port" =~ ^[0-9]+$ ]] && [[ $new_port -ge 1 && $new_port -le 65535 ]]; then
            CEGP_PORT="$new_port"
        else
            print_error "Invalid port number"
        fi
    fi
    
    print_success "CEGP settings updated"
}

# Function to update scaling settings
update_scaling_settings() {
    print_header "UPDATE SCALING SETTINGS"
    
    echo "Current scaling settings:"
    echo "Min replicas: $MIN_REPLICAS"
    echo "Max replicas: $MAX_REPLICAS"
    
    read -p "Enter new minimum replicas (2-20, or press Enter to keep current): " new_min
    if [[ -n "$new_min" ]]; then
        if [[ $new_min -ge 2 && $new_min -le 20 ]]; then
            MIN_REPLICAS="$new_min"
        else
            print_error "Invalid minimum replicas (must be 2-20)"
        fi
    fi
    
    read -p "Enter new maximum replicas ($MIN_REPLICAS-20, or press Enter to keep current): " new_max
    if [[ -n "$new_max" ]]; then
        if [[ $new_max -ge $MIN_REPLICAS && $new_max -le 20 ]]; then
            MAX_REPLICAS="$new_max"
        else
            print_error "Invalid maximum replicas (must be $MIN_REPLICAS-20)"
        fi
    fi

    enforce_storage_scaling_constraints
    
    print_success "Scaling settings updated"
}

# Function to update rate limits
update_rate_limits() {
    print_header "UPDATE RATE LIMITING"
    
    echo "Current rate limits:"
    echo "Per IP per minute: $RATE_LIMIT_IP_PER_MIN"
    echo "Per recipient per minute: $RATE_LIMIT_RCPT_PER_MIN"
    
    read -p "Enter new rate limit per IP per minute (or press Enter to keep current): " new_rate_ip
    if [[ -n "$new_rate_ip" ]]; then
        if [[ "$new_rate_ip" =~ ^[0-9]+$ ]]; then
            RATE_LIMIT_IP_PER_MIN="$new_rate_ip"
        else
            print_error "Invalid rate limit (must be a number)"
        fi
    fi
    
    read -p "Enter new rate limit per recipient per minute (or press Enter to keep current): " new_rate_rcpt
    if [[ -n "$new_rate_rcpt" ]]; then
        if [[ "$new_rate_rcpt" =~ ^[0-9]+$ ]]; then
            RATE_LIMIT_RCPT_PER_MIN="$new_rate_rcpt"
        else
            print_error "Invalid rate limit (must be a number)"
        fi
    fi
    
    print_success "Rate limiting updated"
}

# Function to apply configuration changes
apply_configuration_changes() {
    print_header "APPLYING CONFIGURATION CHANGES"
    
    print_status "Updating deployment configuration..."
    update_deployment_files
    
    print_status "Applying changes to Kubernetes cluster..."
    if [[ "$DEPLOYMENT_TYPE" == "remote" ]]; then
        scp kubernetes/kubernetes-deployment-configured.yaml "$REMOTE_USER@$REMOTE_SERVER:~/cegp-relay-deploy/"
        execute_kubectl "k0s kubectl apply -f ~/cegp-relay-deploy/kubernetes-deployment-configured.yaml"
    else
        execute_kubectl "k0s kubectl apply -f kubernetes/kubernetes-deployment-configured.yaml"
    fi
    
    print_status "Restarting deployment to apply changes..."
    execute_kubectl "k0s kubectl rollout restart deployment cegp-smtp-relay -n $NAMESPACE"
    
    print_status "Waiting for rollout to complete..."
    execute_kubectl "k0s kubectl rollout status deployment cegp-smtp-relay -n $NAMESPACE --timeout=300s"
    
    save_config
    print_success "Configuration changes applied successfully!"
}

# Function to run tests
run_tests() {
    print_header "RUNNING TESTS"
    
    if ! load_config; then
        print_error "No configuration found. Please run installation first."
        return 1
    fi
    
    print_status "Running comprehensive tests..."
    
    if [[ "$DEPLOYMENT_TYPE" == "remote" ]]; then
        # Copy test script to remote server
        scp scripts/quick-test.sh "$REMOTE_USER@$REMOTE_SERVER:~/cegp-relay-deploy/"
        ssh "$REMOTE_USER@$REMOTE_SERVER" "cd ~/cegp-relay-deploy && chmod +x quick-test.sh && ./quick-test.sh"
    else
        if [[ -f "scripts/quick-test.sh" ]]; then
            chmod +x scripts/quick-test.sh
            ./scripts/quick-test.sh
        else
            print_error "Test script not found. Please ensure scripts/quick-test.sh exists."
        fi
    fi
}

# Function to uninstall
uninstall() {
    print_header "UNINSTALL CEGP SMTP RELAY"
    
    if ! load_config; then
        print_error "No configuration found."
        return 1
    fi
    
    print_warning "This will completely remove the CEGP SMTP Relay deployment."
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        print_status "Removing CEGP SMTP Relay..."
        execute_kubectl "k0s kubectl delete namespace $NAMESPACE"
        
        print_status "Cleaning up configuration files..."
        rm -f "$CONFIG_FILE"
        rm -f kubernetes/kubernetes-deployment-configured.yaml
        rm -f "$TEMP_CONFIG"
        
        print_success "CEGP SMTP Relay uninstalled successfully"
    else
        print_status "Uninstall cancelled"
    fi
}

# Main menu function
show_main_menu() {
    while true; do
        clear
        print_header "CEGP SMTP RELAY MANAGEMENT"
        
        if load_config 2>/dev/null; then
            echo -e "${GREEN}✓ Configuration found${NC} - Deployment: $DEPLOYMENT_TYPE ($CLUSTER_TYPE)"
        else
            echo -e "${YELLOW}⚠ No configuration found${NC} - Run installation first"
        fi
        
        echo
        echo "1)  Install/Deploy CEGP SMTP Relay"
        echo "2)  Show deployment status"
        echo "3)  Monitor real-time metrics"
        echo "4)  Manage configuration"
        echo "5)  Run tests"
        echo "6)  View logs"
        echo "7)  Restart deployment"
        echo "8)  Scale deployment"
        echo "9)  Backup configuration"
        echo "10) Restore configuration"
        echo "11) Uninstall"
        echo "12) Exit"
        
        read -p "Enter your choice (1-12): " choice
        
        case $choice in
            1)
                create_config_dir
                get_deployment_type
                get_cegp_config
                get_authorized_domains
                get_authorized_ips
                get_rate_limits
                enforce_storage_scaling_constraints
                save_config
                if [[ "$DEPLOYMENT_TYPE" == "remote" ]]; then
                    setup_remote_kubectl
                fi
                deploy_application
                read -p "Press Enter to continue..."
                ;;
            2)
                show_status
                read -p "Press Enter to continue..."
                ;;
            3)
                monitor_realtime
                ;;
            4)
                manage_configuration
                ;;
            5)
                run_tests
                read -p "Press Enter to continue..."
                ;;
            6)
                if load_config; then
                    print_header "RECENT LOGS"
                    execute_kubectl "k0s kubectl logs -l app=cegp-smtp-relay -n $NAMESPACE --tail=50"
                else
                    print_error "No configuration found"
                fi
                read -p "Press Enter to continue..."
                ;;
            7)
                if load_config; then
                    print_status "Restarting deployment..."
                    execute_kubectl "k0s kubectl rollout restart deployment cegp-smtp-relay -n $NAMESPACE"
                    print_success "Deployment restarted"
                else
                    print_error "No configuration found"
                fi
                read -p "Press Enter to continue..."
                ;;
            8)
                if load_config; then
                    read -p "Enter desired number of replicas ($MIN_REPLICAS-$MAX_REPLICAS): " replicas
                    enforce_storage_scaling_constraints
                    if [[ $replicas -ge $MIN_REPLICAS && $replicas -le $MAX_REPLICAS ]]; then
                        execute_kubectl "k0s kubectl scale deployment cegp-smtp-relay --replicas=$replicas -n $NAMESPACE"
                        print_success "Deployment scaled to $replicas replicas"
                    else
                        print_error "Invalid replica count"
                    fi
                else
                    print_error "No configuration found"
                fi
                read -p "Press Enter to continue..."
                ;;
            9)
                if [[ -f "$CONFIG_FILE" ]]; then
                    cp "$CONFIG_FILE" "./config/deployment-backup-$(date +%Y%m%d-%H%M%S).conf"
                    print_success "Configuration backed up"
                else
                    print_error "No configuration to backup"
                fi
                read -p "Press Enter to continue..."
                ;;
            10)
                echo "Available backups:"
                ls -la ./config/deployment-backup-*.conf 2>/dev/null || echo "No backups found"
                read -p "Enter backup filename to restore (or press Enter to cancel): " backup_file
                if [[ -f "$backup_file" ]]; then
                    cp "$backup_file" "$CONFIG_FILE"
                    print_success "Configuration restored from $backup_file"
                elif [[ -n "$backup_file" ]]; then
                    print_error "Backup file not found"
                fi
                read -p "Press Enter to continue..."
                ;;
            11)
                uninstall
                read -p "Press Enter to continue..."
                ;;
            12)
                print_status "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please select 1-12."
                sleep 2
                ;;
        esac
    done
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check for required commands
    command -v kubectl >/dev/null 2>&1 || command -v k0s >/dev/null 2>&1 || missing_deps+=("kubectl or k0s")
    command -v git >/dev/null 2>&1 || missing_deps+=("git")
    command -v nc >/dev/null 2>&1 || missing_deps+=("netcat")
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_status "Please install the missing dependencies and try again."
        exit 1
    fi
}

# Main execution
main() {
    print_header "CEGP SMTP RELAY INSTALLER"
    print_status "Checking dependencies..."
    check_dependencies
    
    print_success "All dependencies found"
    sleep 1
    
    show_main_menu
}

# Run main function
main "$@"