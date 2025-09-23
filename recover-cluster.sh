#!/bin/bash

# Kind Cluster Recovery Script
# Use this script after system restarts when kubectl commands fail

set -euo pipefail

# Configuration
CLUSTER_NAME="qos"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if Docker is running
check_docker() {
    if ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    log_info "Docker is running"
}

# Check if kind cluster exists
check_cluster_exists() {
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        return 0
    else
        return 1
    fi
}

# Try to recover existing cluster
try_recovery() {
    log_step "Attempting to recover existing cluster..."
    
    # Start all kind containers
    log_info "Starting kind containers..."
    docker start $(docker ps -a --filter "label=io.x-k8s.kind.cluster=${CLUSTER_NAME}" --format "{{.Names}}") 2>/dev/null || true
    
    # Wait for containers to start
    sleep 10
    
    # Test kubectl connection
    if kubectl get nodes &> /dev/null; then
        log_info "✅ Cluster recovery successful!"
        kubectl get nodes
        return 0
    else
        log_warn "❌ Cluster recovery failed"
        return 1
    fi
}

# Full cluster recreation
recreate_cluster() {
    log_step "Recreating cluster from scratch..."
    
    # Delete existing cluster
    if check_cluster_exists; then
        log_info "Deleting existing cluster..."
        kind delete cluster --name "$CLUSTER_NAME"
    fi
    
    # Recreate using deployment script
    log_info "Running deployment script..."
    if [[ -f "$SCRIPT_DIR/qos-depl.sh" ]]; then
        "$SCRIPT_DIR/qos-depl.sh"
    else
        log_error "Deployment script not found: $SCRIPT_DIR/qos-depl.sh"
        exit 1
    fi
}

# Main recovery logic
main() {
    log_info "🔧 Kind Cluster Recovery Script"
    log_info "Cluster: $CLUSTER_NAME"
    
    # Check prerequisites
    check_docker
    
    if ! check_cluster_exists; then
        log_error "Cluster '$CLUSTER_NAME' does not exist. Use './qos-depl.sh' to create it."
        exit 1
    fi
    
    # Try quick recovery first
    if try_recovery; then
        log_info "🎉 Quick recovery successful!"
        exit 0
    fi
    
    # If quick recovery fails, ask user for full recreation
    log_warn "Quick recovery failed. Full cluster recreation is recommended."
    read -p "Do you want to recreate the cluster? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        recreate_cluster
        log_info "🎉 Cluster recreation completed!"
    else
        log_info "Recovery cancelled. You can run this script again or use './qos-depl.sh' manually."
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --force    Force full recreation without prompting"
    echo ""
    echo "This script helps recover your kind cluster after system restarts."
}

# Parse arguments
FORCE_RECREATE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -f|--force)
            FORCE_RECREATE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Execute main function
if [[ "$FORCE_RECREATE" == "true" ]]; then
    check_docker
    recreate_cluster
    log_info "🎉 Forced cluster recreation completed!"
else
    main
fi
