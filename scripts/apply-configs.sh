#!/bin/bash
# apply-configs.sh - Apply Talos configs to all nodes
set -euo pipefail

TALOSCONFIG="./talos/talosconfig"

echo "Applying Talos configurations to nodes..."
echo "Using TALOSCONFIG: ${TALOSCONFIG}"
echo ""

# Control plane nodes
for i in 1 2 3; do
    NODE_NUM=$(printf "%02d" $i)
    IP="192.168.99.10${i}"
    CONFIG="talos/controlplane/controlplane-${NODE_NUM}.yaml"
    
    echo "==> Applying config to controlplane-${NODE_NUM} (${IP})"
    
    if talosctl apply-config \
        --nodes "${IP}" \
        --file "${CONFIG}" \
        --insecure; then
        echo "    ✓ Config applied successfully"
    else
        echo "    ✗ Failed to apply config"
        exit 1
    fi
    
    echo "    Waiting 30s for node to process config..."
    sleep 30
    echo ""
done

# Worker node
echo "==> Applying config to worker-01 (192.168.99.111)"
if talosctl apply-config \
    --nodes 192.168.99.111 \
    --file talos/worker/worker-01.yaml \
    --insecure; then
    echo "    ✓ Config applied successfully"
else
    echo "    ✗ Failed to apply config"
    exit 1
fi

echo ""
echo "All configurations applied successfully!"
echo ""
echo "Next step: Run ./scripts/bootstrap.sh to bootstrap the cluster"
