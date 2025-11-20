#!/bin/bash
# bootstrap.sh - Bootstrap the Talos Kubernetes cluster
set -euo pipefail

export TALOSCONFIG="./talos/talosconfig"
FIRST_CP="192.168.99.101"
VIP="192.168.99.100"

# ... existing bootstrap code ...

echo ""
echo "==> Creating AdGuardHome namespace and password secret"

# Prompt for AdGuardHome username
read -p "Enter AdGuardHome username (default: admin): " ADGUARDHOME_USERNAME
if [ -z "$ADGUARDHOME_USERNAME" ]; then
    ADGUARDHOME_USERNAME="admin"
fi
echo "    ✓ Username set to: ${ADGUARDHOME_USERNAME}"
echo ""

# Prompt for AdGuardHome password with confirmation
while true; do
    read -sp "Enter AdGuardHome password: " ADGUARDHOME_PASSWORD
    echo ""
    read -sp "Confirm AdGuardHome password: " ADGUARDHOME_PASSWORD_CONFIRM
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
    PASSWORD_HASH=$(docker run --rm httpd:alpine htpasswd -nbB "${ADGUARDHOME_USERNAME}" "${ADGUARDHOME_PASSWORD}" | cut -d ":" -f 2)
else
    PASSWORD_HASH=$(htpasswd -nbB "${ADGUARDHOME_USERNAME}" "${ADGUARDHOME_PASSWORD}" | cut -d ":" -f 2)
fi

# Create namespace if it doesn't exist
kubectl --kubeconfig=./kubeconfig create namespace adguardhome --dry-run=client -o yaml | kubectl --kubeconfig=./kubeconfig apply -f -

# Label namespace for PodSecurity
kubectl --kubeconfig=./kubeconfig label namespace adguardhome \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged \
    --overwrite

# Create the secret with BOTH username and password-hash
kubectl --kubeconfig=./kubeconfig create secret generic adguardhome-password \
    --from-literal=password-hash="${PASSWORD_HASH}" \
    --from-literal=username="${ADGUARDHOME_USERNAME}" \
    -n adguardhome \
    --dry-run=client -o yaml | kubectl --kubeconfig=./kubeconfig apply -f -

echo "    ✓ AdGuardHome credentials secret created for user: ${ADGUARDHOME_USERNAME}"

# Clear password variables from memory
unset ADGUARDHOME_USERNAME
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