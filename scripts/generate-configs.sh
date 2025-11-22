#!/bin/bash
# generate-configs.sh - Generate Talos configs for pre-baked images
set -euo pipefail

VIP="192.168.99.100"
CLUSTER_NAME="talos-cluster"
CLUSTER_ENDPOINT="https://${VIP}:6443"

# Generate base configs (using first control plane IP for initial generation)
echo "Generating base configurations..."
talosctl gen config "${CLUSTER_NAME}" "${CLUSTER_ENDPOINT}" \
  --output-dir ./talos \
  --with-secrets secrets.yaml \
  --force

echo "Creating node-specific patches..."

# Control plane patch template (IPs already configured in images)
for i in 1 2 3; do
  NODE_NUM=$(printf "%02d" $i)
  cat > "talos/controlplane/controlplane-${NODE_NUM}-patch.yaml" <<EOF
machine:
  network:
    hostname: controlplane-${NODE_NUM}
    interfaces:
      - deviceSelector:
          physical: true
        vip:
          ip: ${VIP}  # VIP on all control planes
cluster:
  allowSchedulingOnControlPlanes: true
  controlPlane:
    endpoint: ${CLUSTER_ENDPOINT}
EOF
done

# Worker patch (no VIP needed)
cat > talos/worker/worker-01-patch.yaml <<EOF
machine:
  network:
    hostname: worker-01
EOF

echo "Generating final node configurations..."

# Generate patched configs
for i in 1 2 3; do
  NODE_NUM=$(printf "%02d" $i)
  talosctl machineconfig patch \
    talos/controlplane.yaml \
    --patch @talos/controlplane/controlplane-${NODE_NUM}-patch.yaml \
    --output talos/controlplane/controlplane-${NODE_NUM}.yaml
done

talosctl machineconfig patch \
  talos/worker.yaml \
  --patch @talos/worker/worker-01-patch.yaml \
  --output talos/worker/worker-01.yaml

echo ""
echo "✓ Configuration files generated:"
ls -1 talos/controlplane/*.yaml talos/worker/*.yaml

echo ""
echo "Next: Apply configs to booted nodes with pre-configured IPs"
