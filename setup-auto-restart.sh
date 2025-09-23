#!/bin/bash

# Setup Auto-Restart for Kind Cluster Containers
# This script configures Docker containers to automatically restart after system reboots

set -euo pipefail

CLUSTER_NAME="qos"

echo "🔧 Setting up auto-restart for kind cluster containers..."

# Get all kind cluster containers
CONTAINERS=$(docker ps -a --filter "label=io.x-k8s.kind.cluster=${CLUSTER_NAME}" --format "{{.Names}}")

if [[ -z "$CONTAINERS" ]]; then
    echo "❌ No containers found for cluster: $CLUSTER_NAME"
    echo "Make sure the cluster is created first."
    exit 1
fi

echo "Found containers:"
echo "$CONTAINERS"
echo ""

# Update restart policy for each container
for container in $CONTAINERS; do
    echo "Setting restart policy for: $container"
    docker update --restart=unless-stopped "$container"
done

echo ""
echo "✅ Auto-restart policy configured successfully!"
echo ""
echo "Your kind cluster containers will now automatically restart after system reboots."
echo "Note: You may still need to wait a few moments for all services to be ready."
