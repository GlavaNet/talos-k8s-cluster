#!/bin/bash
# bootstrap.sh - Bootstrap the Talos Kubernetes cluster
set -euo pipefail

export TALOSCONFIG="./talos/talosconfig"
FIRST_CP="192.168.99.101"
VIP="192.168.99.100"

echo "Bootstrapping Talos Kubernetes cluster..."
echo ""

echo "==> Bootstrapping etcd on first control plane (${FIRST_CP})"
if talosctl bootstrap \
    --nodes "${FIRST_CP}" \
    --endpoints "${FIRST_CP}"; then
    echo "    ✓ Bootstrap initiated"
else
    echo "    ✗ Bootstrap failed"
    exit 1
fi

echo ""
echo "Waiting for cluster to become healthy (this may take 5-10 minutes on RPi)..."
echo "Monitoring health..."

if talosctl --nodes "${FIRST_CP}" health --wait-timeout 15m; then
    echo ""
    echo "✓ Cluster is healthy!"
else
    echo ""
    echo "✗ Cluster health check timed out"
    echo "Run: talosctl --nodes ${FIRST_CP} dmesg --follow"
    exit 1
fi

echo ""
echo "==> Updating talosconfig to use VIP endpoint"
talosctl config endpoint "${VIP}"

echo ""
echo "==> Testing VIP connectivity"
if talosctl --nodes "${VIP}" version &>/dev/null; then
    echo "    ✓ VIP is responding"
else
    echo "    ⚠ VIP not responding yet, using control plane node"
fi

echo ""
echo "==> Retrieving kubeconfig"
talosctl kubeconfig ./kubeconfig

echo ""
echo "==> Verifying cluster nodes"
kubectl --kubeconfig=./kubeconfig get nodes -o wide

echo ""
echo "✓ Cluster bootstrap complete!"
echo ""
echo "Cluster endpoint: https://${VIP}:6443"
echo "Kubeconfig: ./kubeconfig"
echo ""
echo "Next steps:"
echo "1. Install MetalLB: kubectl apply -f kubernetes/infrastructure/metallb/"
echo "2. Bootstrap Flux: flux bootstrap github ..."
