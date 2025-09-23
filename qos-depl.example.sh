#!/bin/bash

# Enhanced QOS Cluster Deployment Script
# This script automates the complete deployment of the QOS Kind cluster
# with proper error handling, status checking, and resource waiting

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Format and coloring constants
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="qos"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_SECONDS=300

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Script failed. Cleaning up..."
    # Optionally delete the cluster on failure
    # kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
}

trap cleanup_on_error ERR

# Utility functions
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 could not be found. Please install it first."
        exit 1
    fi
}

wait_for_pods() {
    local namespace="$1"
    local label_selector="$2"
    local timeout="${3:-$TIMEOUT_SECONDS}"

    log_info "Waiting for pods in namespace '$namespace' with selector '$label_selector' to be ready..."

    if kubectl wait --for=condition=Ready pods \
        -l "$label_selector" \
        -n "$namespace" \
        --timeout="${timeout}s" 2>/dev/null; then
        log_info "Pods are ready!"
        return 0
    else
        log_warn "Timeout waiting for pods. Checking status..."
        kubectl get pods -n "$namespace" -l "$label_selector"
        return 1
    fi
}

wait_for_nodes() {
    local timeout="${1:-$TIMEOUT_SECONDS}"

    log_info "Waiting for all nodes to be ready..."

    if kubectl wait --for=condition=Ready nodes --all --timeout="${timeout}s"; then
        log_info "All nodes are ready!"
        return 0
    else
        log_error "Timeout waiting for nodes to be ready"
        kubectl get nodes
        return 1
    fi
}

apply_manifest() {
    local manifest_path="$1"
    local description="$2"

    if [[ ! -f "$manifest_path" ]]; then
        log_warn "Manifest not found: $manifest_path - skipping"
        return 0
    fi

    log_step "Applying $description: $(basename "$manifest_path")"

    if kubectl apply -f "$manifest_path"; then
        log_info "Successfully applied $description"
        return 0
    else
        log_error "Failed to apply $description"
        return 1
    fi
}

check_cluster_exists() {
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        return 0
    else
        return 1
    fi
}

# Main deployment functions
check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check required tools
    check_command "kind"
    check_command "kubectl"
    check_command "docker"

    # Check if Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker first."
        exit 1
    fi

    # Check system file descriptor limits
    local current_limit=$(ulimit -n)
    if [[ $current_limit -lt 65536 ]]; then
        log_warn "Current file descriptor limit ($current_limit) is low for Kubernetes."
        log_warn "Consider running: ulimit -n 65536"
        log_warn "Proceeding anyway, but you may encounter 'too many open files' errors."
    fi

    log_info "Prerequisites check completed successfully"
}

create_cluster() {
    log_step "Creating Kind cluster '$CLUSTER_NAME'..."

    if check_cluster_exists; then
        log_warn "Cluster '$CLUSTER_NAME' already exists."
        read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting existing cluster..."
            kind delete cluster --name "$CLUSTER_NAME"
        else
            log_info "Using existing cluster"
            return 0
        fi
    fi

    local config_file="$SCRIPT_DIR/common/manifests/kind-config.yaml"
    if [[ ! -f "$config_file" ]]; then
        log_error "Kind config file not found: $config_file"
        exit 1
    fi

    log_info "Creating cluster with config: $config_file"
    if kind create cluster --config "$config_file" --name "$CLUSTER_NAME"; then
        log_info "Cluster created successfully"
    else
        log_error "Failed to create cluster"
        exit 1
    fi

    # Wait for nodes to be ready
    wait_for_nodes

    # Display cluster info
    log_info "Cluster information:"
    kubectl cluster-info --context "kind-$CLUSTER_NAME"
    kubectl get nodes -o wide
}

deploy_common_manifests() {
    log_step "Deploying common infrastructure manifests..."

    local common_dir="$SCRIPT_DIR/common/manifests"

    # Deploy in specific order for dependencies
    local manifests=(
        "kind-ingress-nginx-depl.yaml:NGINX Ingress Controller"
        "patch-def-sa.yaml:Default Service Account Patch"
    )

    for manifest_info in "${manifests[@]}"; do
        IFS=':' read -r manifest_file description <<< "$manifest_info"
        apply_manifest "$common_dir/$manifest_file" "$description"
    done

    # Wait for ingress controller to be ready
    log_info "Waiting for NGINX Ingress Controller to be ready..."
    if wait_for_pods "ingress-nginx" "app.kubernetes.io/component=controller" 600; then
        log_info "NGINX Ingress Controller is ready"
    else
        log_warn "NGINX Ingress Controller may not be fully ready, but continuing..."
    fi

    # Check if ingress controller service is available
    log_info "Checking ingress controller service..."
    kubectl get svc -n ingress-nginx ingress-nginx-controller || log_warn "Ingress service not found"
}

deploy_qoc_manifests() {
    log_step "Deploying QOC (Quick Order Customer) manifests..."

    local qoc_dir="$SCRIPT_DIR/qoc/manifests"

    # Check if directory exists and has manifests
    if [[ ! -d "$qoc_dir" ]]; then
        log_warn "QOC manifests directory not found: $qoc_dir"
        return 0
    fi

    # Apply all YAML files in the directory
    for manifest_file in "$qoc_dir"/*.yaml; do
        if [[ -f "$manifest_file" ]]; then
            local filename=$(basename "$manifest_file")
            apply_manifest "$manifest_file" "QOC $filename"
        fi
    done

    log_info "QOC manifests deployment completed"
}

deploy_qos_manifests() {
    log_step "Deploying QOS (Quick Order System) manifests..."

    local qos_dir="$SCRIPT_DIR/qos/manifests"

    # Check if directory exists
    if [[ ! -d "$qos_dir" ]]; then
        log_warn "QOS manifests directory not found: $qos_dir"
        return 0
    fi

    # Create MongoDB secret if it doesn't exist
    log_info "Checking MongoDB secret..."
    if ! kubectl get secret mongodb-secret >/dev/null 2>&1; then
        log_warn "MongoDB secret not found. Creating with default credentials..."
        log_warn "⚠️  SECURITY WARNING: Using default password for development only!"
        log_warn "⚠️  For production, run './create-mongodb-secret.sh' to set a secure password."

        # Create secret with default credentials (for development/testing only)
        kubectl create secret generic mongodb-secret \
            --from-literal=MONGODB_APP_USER=USERNAME \
            --from-literal=MONGODB_APP_PASSWORD=PASSWORD \
            >/dev/null 2>&1

        if [ $? -eq 0 ]; then
            log_info "✓ MongoDB secret created with default credentials"
        else
            log_error "✗ Failed to create MongoDB secret"
            return 1
        fi
    else
        log_info "✓ MongoDB secret already exists"
    fi

    # Deploy in specific order for dependencies
    # Secrets and ConfigMaps must be deployed before Deployments that reference them
    # Storage components must be deployed before StatefulSets
    # Services must be deployed before Ingress that references them
    local manifests=(
        "gitlab-regcred.yaml:QOS GitLab Registry Credentials"
        "qos-secret.yaml:QOS Application Secrets"
        "qos-cfg.yaml:QOS Application ConfigMap"
        "mongodb-storage.yaml:MongoDB Storage Components (PV, StorageClass)"
        "mongodb-config.yaml:MongoDB Configuration ConfigMap"
        "mongodb-service.yaml:MongoDB Services (Headless & ClusterIP)"
        "mongodb-statefulset.yaml:MongoDB StatefulSet"
        "qos-frontend-depl.yaml:QOS Frontend Deployment"
        "qos-frontend-svc.yaml:QOS Frontend NodePort Service"
        "qos-frontend-cip-svc.yaml:QOS Frontend ClusterIP Service"
        "qos-frontend-ingress.yaml:QOS Frontend Ingress (SSL Termination)"
        "qos-backend-depl.yaml:QOS Backend Deployment"
        "qos-backend-svc.yaml:QOS Backend Service"
    )

    for manifest_info in "${manifests[@]}"; do
        IFS=':' read -r manifest_file description <<< "$manifest_info"
        apply_manifest "$qos_dir/$manifest_file" "$description"
    done

    # Wait for MongoDB to be ready first (database dependency)
    log_info "Waiting for MongoDB StatefulSet to be ready..."
    if wait_for_pods "default" "app=mongodb" 300; then
        log_info "MongoDB is ready"
        # Additional check for MongoDB service
        if kubectl get service mongodb &> /dev/null; then
            log_info "MongoDB service is available"
        else
            log_warn "MongoDB service may have issues"
        fi
    else
        log_warn "MongoDB may not be fully ready"
        kubectl get pods -l app=mongodb || true
        kubectl get pvc -l app=mongodb || true
    fi

    # Wait for QOS frontend to be ready
    log_info "Waiting for QOS frontend to be ready..."
    if wait_for_pods "default" "app=qos-frontend-pod" 300; then
        log_info "QOS frontend is ready"
    else
        log_warn "QOS frontend may not be fully ready"
        kubectl get pods -l app=qos-frontend-pod || true
    fi

    # Wait for QOS backend to be ready
    log_info "Waiting for QOS backend to be ready..."
    if wait_for_pods "default" "app=qos-backend-pod" 300; then
        log_info "QOS backend is ready"
    else
        log_warn "QOS backend may not be fully ready"
        kubectl get pods -l app=qos-backend-pod || true
    fi
}

verify_deployment() {
    log_step "Verifying deployment status..."

    # Check cluster status
    log_info "Cluster nodes:"
    kubectl get nodes -o wide

    # Check all pods across namespaces
    log_info "All pods status:"
    kubectl get pods --all-namespaces -o wide

    # Check services
    log_info "Services:"
    kubectl get svc --all-namespaces

    # Check ingress resources
    log_info "Ingress resources:"
    kubectl get ingress --all-namespaces || log_warn "No ingress resources found"

    # Specific checks for critical components
    log_info "Checking critical components..."

    # Check ingress controller
    if kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers | grep -q "Running"; then
        log_info "✓ NGINX Ingress Controller is running"
    else
        log_warn "✗ NGINX Ingress Controller may have issues"
    fi

    # Check QOS resources
    if kubectl get secret qos-secret --no-headers 2>/dev/null | grep -q "qos-secret"; then
        log_info "✓ QOS Secret is deployed"
    else
        log_warn "✗ QOS Secret not found"
    fi

    if kubectl get configmap qos-cfg --no-headers 2>/dev/null | grep -q "qos-cfg"; then
        log_info "✓ QOS ConfigMap is deployed"
    else
        log_warn "✗ QOS ConfigMap not found"
    fi

    if kubectl get pods -l app=qos-frontend-pod --no-headers 2>/dev/null | grep -q "Running"; then
        log_info "✓ QOS Frontend is running"
    else
        log_warn "✗ QOS Frontend not found or not running"
    fi

    if kubectl get pods -l app=qos-backend-pod --no-headers 2>/dev/null | grep -q "Running"; then
        log_info "✓ QOS Backend is running"
    else
        log_warn "✗ QOS Backend not found or not running"
    fi

    # Check MongoDB resources
    if kubectl get secret mongodb-secret --no-headers 2>/dev/null | grep -q "mongodb-secret"; then
        log_info "✓ MongoDB Secret is deployed"
    else
        log_warn "✗ MongoDB Secret not found"
    fi

    if kubectl get configmap mongodb-config --no-headers 2>/dev/null | grep -q "mongodb-config"; then
        log_info "✓ MongoDB ConfigMap is deployed"
    else
        log_warn "✗ MongoDB ConfigMap not found"
    fi

    if kubectl get service mongodb --no-headers 2>/dev/null | grep -q "mongodb"; then
        log_info "✓ MongoDB Service is deployed"
    else
        log_warn "✗ MongoDB Service not found"
    fi

    if kubectl get statefulset mongodb --no-headers 2>/dev/null | grep -q "mongodb"; then
        log_info "✓ MongoDB StatefulSet is deployed"
        # Check if MongoDB pod is running
        if kubectl get pods -l app=mongodb --no-headers 2>/dev/null | grep -q "Running"; then
            log_info "✓ MongoDB is running"
        else
            log_warn "✗ MongoDB pod not running"
        fi
    else
        log_warn "✗ MongoDB StatefulSet not found"
    fi

    # Check MongoDB PVC
    if kubectl get pvc -l app=mongodb --no-headers 2>/dev/null | grep -q "Bound"; then
        log_info "✓ MongoDB storage is bound"
    else
        log_warn "✗ MongoDB storage not bound or not found"
    fi

    # Display access information
    log_info "Access Information:"
    echo "  - Cluster context: kind-$CLUSTER_NAME"
    echo "  - To access services: kubectl port-forward or use ingress"
    echo "  - To delete cluster: kind delete cluster --name $CLUSTER_NAME"
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -v, --verify   Only run verification (skip deployment)"
    echo "  -c, --clean    Delete existing cluster before creating new one"
    echo ""
    echo "This script deploys the complete QOS Kind cluster with:"
    echo "  - Kind cluster with multiple nodes"
    echo "  - NGINX Ingress Controller"
    echo "  - GitLab registry credentials"
    echo "  - QOS application secrets and configuration"
    echo "  - QOS frontend with SSL termination ingress"
    echo "  - QOC and QOS application manifests"
    echo "  - ClusterIP and NodePort services for different access patterns"
}

# Main execution
main() {
    local verify_only=false
    local force_clean=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verify)
                verify_only=true
                shift
                ;;
            -c|--clean)
                force_clean=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    log_info "Starting QOS Cluster Deployment Script"
    log_info "Script directory: $SCRIPT_DIR"

    # Always check prerequisites
    check_prerequisites

    if [[ "$verify_only" == "true" ]]; then
        log_info "Running verification only..."
        verify_deployment
        exit 0
    fi

    # Force clean if requested
    if [[ "$force_clean" == "true" ]] && check_cluster_exists; then
        log_info "Force cleaning existing cluster..."
        kind delete cluster --name "$CLUSTER_NAME"
    fi

    # Main deployment sequence
    create_cluster
    deploy_common_manifests
    deploy_qoc_manifests
    deploy_qos_manifests
    verify_deployment

    log_info "🎉 QOS Cluster deployment completed successfully!"
    log_info "Use 'kubectl get pods --all-namespaces' to check all pods"
    log_info "Use '$0 --verify' to run verification checks"
}

# Execute main function with all arguments
main "$@"
