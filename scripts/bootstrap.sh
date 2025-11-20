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
echo "==> Creating AdGuardHome namespace and password secret"

# Prompt for AdGuardHome password with confirmation
while true; do
    read -sp "Enter AdGuardHome admin password: " ADGUARDHOME_PASSWORD
    echo ""
    read -sp "Confirm AdGuardHome admin password: " ADGUARDHOME_PASSWORD_CONFIRM
    echo ""
    
    if [ "$ADGUARDHOME_PASSWORD" = "$ADGUARDHOME_PASSWORD_CONFIRM" ]; then
        if [ -z "$ADGUARDHOME_PASSWORD" ]; then
            echo "    ✗ Password cannot be empty. Please try again."
            echo ""
        else
            echo "    ✓ Passwords match"
            break
        fi
    else
        echo "    ✗ Passwords do not match. Please try again."
        echo ""
    fi
done

# Check if htpasswd is available
if ! command -v htpasswd &> /dev/null; then
    echo "    ⚠ htpasswd not found, using Docker to generate hash..."
    PASSWORD_HASH=$(docker run --rm httpd:alpine htpasswd -nbB admin "${ADGUARDHOME_PASSWORD}" | cut -d ":" -f 2)
else
    PASSWORD_HASH=$(htpasswd -nbB admin "${ADGUARDHOME_PASSWORD}" | cut -d ":" -f 2)
fi

# Create namespace if it doesn't exist
kubectl --kubeconfig=./kubeconfig create namespace adguardhome --dry-run=client -o yaml | kubectl --kubeconfig=./kubeconfig apply -f -

# Label namespace for PodSecurity
kubectl --kubeconfig=./kubeconfig label namespace adguardhome \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged \
    --overwrite

# Create the secret
kubectl --kubeconfig=./kubeconfig create secret generic adguardhome-password \
    --from-literal=password-hash="${PASSWORD_HASH}" \
    -n adguardhome \
    --dry-run=client -o yaml | kubectl --kubeconfig=./kubeconfig apply -f -

echo "    ✓ AdGuardHome password secret created"

# Clear password variables from memory
unset ADGUARDHOME_PASSWORD
unset ADGUARDHOME_PASSWORD_CONFIRM
unset PASSWORD_HASH

echo ""
echo "✓ Cluster bootstrap complete!"
echo ""
echo "Cluster endpoint: https://${VIP}:6443"
echo "Kubeconfig: ./kubeconfig"
echo ""
echo "Next steps:"
echo "1. Install MetalLB: kubectl apply -f kubernetes/infrastructure/metallb/"
echo "2. Bootstrap Flux: flux bootstrap github ..."
echo "3. AdGuardHome will use the password you just set"