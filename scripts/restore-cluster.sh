#!/bin/bash
# Cluster restore script for disaster recovery
# Use this to restore from a backup archive

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Usage information
usage() {
    cat << EOF
Usage: $0 <backup-archive.tar.gz>

Restore Talos cluster from a backup archive.

Examples:
  $0 ~/cluster-backups/cluster-backup-20241121-020000.tar.gz
  $0 cluster-backup-latest.tar.gz

Restore Process:
  1. Extract backup archive
  2. Restore Talos secrets and configs
  3. Optionally restore etcd snapshot
  4. Optionally restore Kubernetes resources

Prerequisites:
  - New SD cards flashed with Talos
  - All nodes booted and reachable
  - talosctl and kubectl installed

EOF
    exit 1
}

# Check arguments
if [ $# -ne 1 ]; then
    usage
fi

BACKUP_ARCHIVE="$1"

# Verify backup archive exists
if [ ! -f "${BACKUP_ARCHIVE}" ]; then
    echo -e "${RED}✗ Backup archive not found: ${BACKUP_ARCHIVE}${NC}"
    exit 1
fi

echo "========================================="
echo "Cluster Disaster Recovery"
echo "========================================="
echo "Backup: ${BACKUP_ARCHIVE}"
echo ""

# Extract backup
TEMP_DIR=$(mktemp -d)
echo -e "${BLUE}Extracting backup archive...${NC}"
tar xzf "${BACKUP_ARCHIVE}" -C "${TEMP_DIR}"

# Find the extracted directory
BACKUP_DIR=$(find "${TEMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -1)

if [ ! -d "${BACKUP_DIR}" ]; then
    echo -e "${RED}✗ Failed to extract backup${NC}"
    rm -rf "${TEMP_DIR}"
    exit 1
fi

echo -e "${GREEN}✓ Backup extracted to ${BACKUP_DIR}${NC}"

# Display manifest
if [ -f "${BACKUP_DIR}/MANIFEST.txt" ]; then
    echo -e "\n${YELLOW}Backup Manifest:${NC}"
    cat "${BACKUP_DIR}/MANIFEST.txt"
fi

# Confirm restore
echo -e "\n${YELLOW}⚠️  WARNING: This will restore cluster configuration${NC}"
echo -e "${YELLOW}Continue with restore? (yes/no)${NC}"
read -r CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Restore cancelled${NC}"
    rm -rf "${TEMP_DIR}"
    exit 0
fi

# 1. Restore Talos secrets
echo -e "\n${BLUE}[1/4]${NC} Restoring Talos secrets..."

if [ -f "${BACKUP_DIR}/talos/secrets.yaml" ]; then
    # Copy secrets.yaml to root directory
    cp "${BACKUP_DIR}/talos/secrets.yaml" ./
    echo -e "${GREEN}✓ Restored secrets.yaml to root directory${NC}"
else
    echo -e "${RED}✗ secrets.yaml not found in backup${NC}"
    echo "  Cannot proceed without secrets"
    rm -rf "${TEMP_DIR}"
    exit 1
fi

if [ -f "${BACKUP_DIR}/talos/talosconfig" ]; then
    # Ensure talos directory exists
    mkdir -p talos
    # Copy talosconfig to talos/ directory
    cp "${BACKUP_DIR}/talos/talosconfig" talos/
    export TALOSCONFIG="$(pwd)/talos/talosconfig"
    echo -e "${GREEN}✓ Restored talosconfig to talos/ directory${NC}"
fi

if [ -d "${BACKUP_DIR}/talos/controlplane" ]; then
    mkdir -p talos
    cp -r "${BACKUP_DIR}/talos/controlplane" talos/
    echo -e "${GREEN}✓ Restored control plane configs${NC}"
fi

if [ -d "${BACKUP_DIR}/talos/worker" ]; then
    mkdir -p talos
    cp -r "${BACKUP_DIR}/talos/worker" talos/
    echo -e "${GREEN}✓ Restored worker configs${NC}"
fi

# 2. Restore kubeconfig
echo -e "\n${BLUE}[2/4]${NC} Restoring kubeconfig..."

if [ -f "${BACKUP_DIR}/kubeconfig" ]; then
    cp "${BACKUP_DIR}/kubeconfig" ./
    export KUBECONFIG="$(pwd)/kubeconfig"
    echo -e "${GREEN}✓ Restored kubeconfig${NC}"
else
    echo -e "${YELLOW}⚠ kubeconfig not found in backup${NC}"
fi

# 3. etcd restore (optional)
echo -e "\n${BLUE}[3/4]${NC} etcd restore..."

if [ -f "${BACKUP_DIR}/etcd/snapshot.db" ]; then
    echo -e "${YELLOW}Do you want to restore etcd snapshot? (yes/no)${NC}"
    echo "  Only needed if cluster state is corrupted or lost"
    read -r RESTORE_ETCD
    
    if [ "$RESTORE_ETCD" = "yes" ]; then
        echo -e "${YELLOW}Enter control plane IP (default: 192.168.99.101):${NC}"
        read -r CP_IP
        CP_IP=${CP_IP:-192.168.99.101}
        
        echo -e "${YELLOW}Copying snapshot to node (/tmp)...${NC}"
        # Use talosctl write to copy file to node
        cat "${BACKUP_DIR}/etcd/snapshot.db" | \
            talosctl --nodes ${CP_IP} write /tmp/etcd-restore.db
        
        echo -e "${YELLOW}Restoring etcd from snapshot...${NC}"
        talosctl --nodes ${CP_IP} \
            etcd snapshot --restore-source=/tmp/etcd-restore.db
        
        echo -e "${GREEN}✓ etcd restored${NC}"
        echo -e "${YELLOW}⚠️  Wait 2-3 minutes for cluster to stabilize${NC}"
    else
        echo -e "${YELLOW}⚠ Skipping etcd restore${NC}"
    fi
else
    echo -e "${YELLOW}⚠ etcd snapshot not found in backup${NC}"
fi

# 4. Kubernetes resources restore (optional)
echo -e "\n${BLUE}[4/4]${NC} Kubernetes resources..."

if [ -d "${BACKUP_DIR}/kubernetes" ]; then
    echo -e "${YELLOW}Do you want to restore Kubernetes resources? (yes/no)${NC}"
    echo "  This will restore all deployments, services, configs, etc."
    read -r RESTORE_K8S
    
    if [ "$RESTORE_K8S" = "yes" ]; then
        # Wait for cluster to be ready
        echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
        kubectl wait --for=condition=Ready nodes --all --timeout=300s 2>/dev/null || \
            echo -e "${YELLOW}⚠ Cluster may not be fully ready${NC}"
        
        # Restore resources in order
        if [ -f "${BACKUP_DIR}/kubernetes/crds.yaml" ]; then
            echo -e "${YELLOW}Restoring CRDs...${NC}"
            kubectl apply -f "${BACKUP_DIR}/kubernetes/crds.yaml" || \
                echo -e "${YELLOW}⚠ Some CRDs may have failed${NC}"
        fi
        
        if [ -f "${BACKUP_DIR}/kubernetes/storageclasses.yaml" ]; then
            echo -e "${YELLOW}Restoring storage classes...${NC}"
            kubectl apply -f "${BACKUP_DIR}/kubernetes/storageclasses.yaml" || \
                echo -e "${YELLOW}⚠ Some storage classes may have failed${NC}"
        fi
        
        if [ -f "${BACKUP_DIR}/kubernetes/volumes.yaml" ]; then
            echo -e "${YELLOW}Restoring volumes...${NC}"
            kubectl apply -f "${BACKUP_DIR}/kubernetes/volumes.yaml" || \
                echo -e "${YELLOW}⚠ Some volumes may have failed${NC}"
        fi
        
        if [ -f "${BACKUP_DIR}/kubernetes/configs.yaml" ]; then
            echo -e "${YELLOW}Restoring configs...${NC}"
            kubectl apply -f "${BACKUP_DIR}/kubernetes/configs.yaml" || \
                echo -e "${YELLOW}⚠ Some configs may have failed${NC}"
        fi
        
        if [ -f "${BACKUP_DIR}/kubernetes/all-resources.yaml" ]; then
            echo -e "${YELLOW}Restoring all resources...${NC}"
            kubectl apply -f "${BACKUP_DIR}/kubernetes/all-resources.yaml" || \
                echo -e "${YELLOW}⚠ Some resources may have failed${NC}"
        fi
        
        echo -e "${GREEN}✓ Kubernetes resources restored${NC}"
    else
        echo -e "${YELLOW}⚠ Skipping Kubernetes restore${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Kubernetes resources not found in backup${NC}"
fi

# Cleanup
rm -rf "${TEMP_DIR}"

# Summary
echo -e "\n========================================="
echo -e "${GREEN}Restore Complete!${NC}"
echo "========================================="
echo ""
echo "Restored components:"
echo "  ✓ Talos secrets and configs"
[ -f "kubeconfig" ] && echo "  ✓ kubeconfig"
[ "$RESTORE_ETCD" = "yes" ] && echo "  ✓ etcd snapshot"
[ "$RESTORE_K8S" = "yes" ] && echo "  ✓ Kubernetes resources"
echo ""
echo "Next steps:"
echo "  1. Verify cluster health:"
echo "     kubectl get nodes"
echo "     kubectl get pods -A"
echo "     talosctl --nodes 192.168.99.101 health"
echo ""
echo "  2. Check etcd health:"
echo "     talosctl --nodes 192.168.99.101 etcdctl member list"
echo "     talosctl --nodes 192.168.99.101 etcdctl endpoint health --cluster"
echo ""
echo "  3. Verify applications:"
echo "     kubectl get all -A"
echo ""
echo "  4. Review logs if issues occur:"
echo "     talosctl --nodes 192.168.99.101 logs kubelet"
echo "     kubectl logs -n kube-system <pod-name>"
echo ""
echo "========================================="

exit 0