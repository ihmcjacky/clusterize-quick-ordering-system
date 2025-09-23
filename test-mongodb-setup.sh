#!/bin/bash

# MongoDB Setup Testing Script
# This script validates the MongoDB StatefulSet deployment and connectivity

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Test MongoDB deployment
test_mongodb_deployment() {
    log_step "Testing MongoDB deployment..."
    
    # Check if StatefulSet exists
    if kubectl get statefulset mongodb &> /dev/null; then
        log_info "✓ MongoDB StatefulSet exists"
        
        # Check StatefulSet status
        local ready_replicas=$(kubectl get statefulset mongodb -o jsonpath='{.status.readyReplicas}')
        local desired_replicas=$(kubectl get statefulset mongodb -o jsonpath='{.spec.replicas}')
        
        if [[ "$ready_replicas" == "$desired_replicas" ]]; then
            log_info "✓ MongoDB StatefulSet is ready ($ready_replicas/$desired_replicas)"
        else
            log_warn "✗ MongoDB StatefulSet not fully ready ($ready_replicas/$desired_replicas)"
        fi
    else
        log_error "✗ MongoDB StatefulSet not found"
        return 1
    fi
    
    # Check if pods are running
    if kubectl get pods -l app=mongodb --no-headers | grep -q "Running"; then
        log_info "✓ MongoDB pods are running"
    else
        log_error "✗ MongoDB pods are not running"
        kubectl get pods -l app=mongodb
        return 1
    fi
    
    # Check services
    if kubectl get service mongodb &> /dev/null; then
        log_info "✓ MongoDB ClusterIP service exists"
    else
        log_error "✗ MongoDB ClusterIP service not found"
    fi
    
    if kubectl get service mongodb-headless &> /dev/null; then
        log_info "✓ MongoDB headless service exists"
    else
        log_error "✗ MongoDB headless service not found"
    fi
    
    # Check PVC
    if kubectl get pvc -l app=mongodb --no-headers | grep -q "Bound"; then
        log_info "✓ MongoDB PVC is bound"
    else
        log_warn "✗ MongoDB PVC not bound"
        kubectl get pvc -l app=mongodb
    fi
}

# Test MongoDB connectivity
test_mongodb_connectivity() {
    log_step "Testing MongoDB connectivity..."
    
    # Get MongoDB pod name
    local mongodb_pod=$(kubectl get pods -l app=mongodb -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -z "$mongodb_pod" ]]; then
        log_error "No MongoDB pod found"
        return 1
    fi
    
    log_info "Testing connectivity to pod: $mongodb_pod"

    # Get credentials from secret
    log_info "Retrieving MongoDB credentials from secret..."
    local mongodb_user=$(kubectl get secret mongodb-secret -o jsonpath='{.data.MONGODB_APP_USER}' | base64 -d 2>/dev/null)
    local mongodb_pass=$(kubectl get secret mongodb-secret -o jsonpath='{.data.MONGODB_APP_PASSWORD}' | base64 -d 2>/dev/null)

    if [[ -z "$mongodb_user" || -z "$mongodb_pass" ]]; then
        log_error "Failed to retrieve MongoDB credentials from secret 'mongodb-secret'"
        log_error "Please ensure the secret exists and contains MONGODB_APP_USER and MONGODB_APP_PASSWORD"
        return 1
    fi

    # Test basic connectivity
    if kubectl exec "$mongodb_pod" -- mongosh --quiet --eval "db.adminCommand('ping')" &> /dev/null; then
        log_info "✓ MongoDB is responding to ping"
    else
        log_error "✗ MongoDB is not responding"
        return 1
    fi

    # Test authentication
    log_info "Testing MongoDB authentication..."
    if kubectl exec "$mongodb_pod" -- mongosh --quiet -u "$mongodb_user" -p "$mongodb_pass" --authenticationDatabase quick-order-system-bigmenu --eval "db.adminCommand('listDatabases')" &> /dev/null; then
        log_info "✓ MongoDB authentication successful"
    else
        log_error "✗ MongoDB authentication failed"
        return 1
    fi

    # Test database access
    log_info "Testing database access..."
    if kubectl exec "$mongodb_pod" -- mongosh --quiet -u "$mongodb_user" -p "$mongodb_pass" --authenticationDatabase quick-order-system-bigmenu --eval "db.stats()" &> /dev/null; then
        log_info "✓ Database access successful"
    else
        log_error "✗ Database access failed"
        return 1
    fi
}

# Test data persistence
test_data_persistence() {
    log_step "Testing data persistence..."
    
    local mongodb_pod=$(kubectl get pods -l app=mongodb -o jsonpath='{.items[0].metadata.name}')

    # Get credentials from secret
    local mongodb_user=$(kubectl get secret mongodb-secret -o jsonpath='{.data.MONGODB_APP_USER}' | base64 -d 2>/dev/null)
    local mongodb_pass=$(kubectl get secret mongodb-secret -o jsonpath='{.data.MONGODB_APP_PASSWORD}' | base64 -d 2>/dev/null)

    if [[ -z "$mongodb_user" || -z "$mongodb_pass" ]]; then
        log_error "Failed to retrieve MongoDB credentials from secret"
        return 1
    fi

    # Insert test data
    log_info "Inserting test data..."
    kubectl exec "$mongodb_pod" -- mongosh --quiet -u "$mongodb_user" -p "$mongodb_pass" --authenticationDatabase quick-order-system-bigmenu --eval "
        db.test_collection.insertOne({
            test_id: 'persistence_test_$(date +%s)',
            message: 'This is a persistence test',
            timestamp: new Date()
        })
    " &> /dev/null

    # Verify data exists
    local count=$(kubectl exec "$mongodb_pod" -- mongosh --quiet -u "$mongodb_user" -p "$mongodb_pass" --authenticationDatabase quick-order-system-bigmenu --eval "db.test_collection.countDocuments({})" | tail -1)
    
    if [[ "$count" -gt 0 ]]; then
        log_info "✓ Data persistence test successful (found $count documents)"
    else
        log_error "✗ Data persistence test failed"
        return 1
    fi
}

# Test service discovery
test_service_discovery() {
    log_step "Testing service discovery..."
    
    # Create a temporary pod for testing
    kubectl run mongodb-test --image=mongo:7.0 --rm -it --restart=Never -- /bin/bash -c "
        echo 'Testing service discovery...'
        if mongosh --quiet mongodb://mongodb.default.svc.cluster.local:27017 --eval 'db.adminCommand(\"ping\")' &> /dev/null; then
            echo '✓ Service discovery successful'
            exit 0
        else
            echo '✗ Service discovery failed'
            exit 1
        fi
    " &> /dev/null
    
    if [[ $? -eq 0 ]]; then
        log_info "✓ Service discovery test passed"
    else
        log_warn "✗ Service discovery test failed"
    fi
}

# Main test function
main() {
    log_info "Starting MongoDB setup validation..."
    
    # Run all tests
    test_mongodb_deployment
    test_mongodb_connectivity
    test_data_persistence
    test_service_discovery
    
    log_info "MongoDB setup validation completed!"
    log_info "Your MongoDB StatefulSet is ready for use."
    
    # Display connection information
    echo
    log_info "Connection Information:"
    echo "  Internal Service: mongodb.default.svc.cluster.local:27017"
    echo "  Database: quick-order-system-bigmenu"
    echo "  Username: [stored in mongodb-secret]"
    echo "  Password: [stored in mongodb-secret]"
    echo
    log_info "To get connection details from secret:"
    echo "  MONGODB_USER=\$(kubectl get secret mongodb-secret -o jsonpath='{.data.MONGODB_APP_USER}' | base64 -d)"
    echo "  MONGODB_PASS=\$(kubectl get secret mongodb-secret -o jsonpath='{.data.MONGODB_APP_PASSWORD}' | base64 -d)"
    echo
    log_info "Connection string template for LoopbackJS:"
    echo "  mongodb://\${MONGODB_USER}:\${MONGODB_PASS}@mongodb.default.svc.cluster.local:27017/quick-order-system-bigmenu"
}

# Execute main function
main "$@"
