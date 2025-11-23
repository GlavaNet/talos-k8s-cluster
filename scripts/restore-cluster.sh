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
  2. Restore Talos secrets (from backup OR secure vault)
  3. Restore Talos configs
  4. Optionally restore etcd snapshot
  5. Optionally restore Kubernetes resources

Prerequisites:
  - New SD cards flashed with Talos
  - All nodes booted and reachable
  - talosctl and kubectl installed
  - Access to secrets (if not in backup)

Secret Vault Locations:
  If secrets are not in the backup, you'll need to retrieve them from:
  • 1Password vault "Cluster Secrets"
  • Encrypted USB drive
  • ~/secure-vault/cluster-secrets/
  • S3 bucket: s3://YOUR-COMPANY-cluster-secrets

Note: Modern backups exclude secrets for security.
      Script will guide you through retrieval if needed.

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

# Check if secrets are in the backup
SECRETS_IN_BACKUP=false
if [ -f "${BACKUP_DIR}/talos/secrets.yaml" ]; then
    SECRETS_IN_BACKUP=true
fi

# Check if there's a reminder file indicating secrets were excluded
if [ -f "${BACKUP_DIR}/talos/SECRETS_NOT_INCLUDED.txt" ]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⚠️  SECRETS NOT IN BACKUP${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    cat "${BACKUP_DIR}/talos/SECRETS_NOT_INCLUDED.txt"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
fi

if [ "$SECRETS_IN_BACKUP" = true ]; then
    # Secrets found in backup - restore them
    echo -e "${GREEN}✓ Secrets found in backup${NC}"
    cp "${BACKUP_DIR}/talos/secrets.yaml" ./
    echo -e "${GREEN}✓ Restored secrets.yaml to root directory${NC}"
    
    if [ -f "${BACKUP_DIR}/talos/talosconfig" ]; then
        mkdir -p talos
        cp "${BACKUP_DIR}/talos/talosconfig" talos/
        export TALOSCONFIG="$(pwd)/talos/talosconfig"
        echo -e "${GREEN}✓ Restored talosconfig to talos/ directory${NC}"
    fi
else
    # Secrets NOT in backup - need to retrieve from vault
    echo -e "${YELLOW}⚠️  Secrets not found in backup${NC}"
    echo -e "${YELLOW}You need to retrieve secrets from your secure vault${NC}"
    echo ""
    echo "Secret vault locations (check one):"
    echo "  1. 1Password vault 'Cluster Secrets'"
    echo "  2. Encrypted USB drive"
    echo "  3. ~/secure-vault/cluster-secrets/"
    echo "  4. S3 bucket: s3://YOUR-COMPANY-cluster-secrets"
    echo ""
    
    # Check if secrets exist in local secure vault
    SECURE_VAULT="${HOME}/secure-vault/cluster-secrets"
    if [ -f "${SECURE_VAULT}/secrets-latest.yaml" ]; then
        echo -e "${GREEN}✓ Found secrets in local vault: ${SECURE_VAULT}${NC}"
        echo -e "\n${YELLOW}Use secrets from local vault? (yes/no)${NC}"
        read -r USE_LOCAL_VAULT
        
        if [ "$USE_LOCAL_VAULT" = "yes" ]; then
            cp "${SECURE_VAULT}/secrets-latest.yaml" ./secrets.yaml
            echo -e "${GREEN}✓ Copied secrets.yaml from vault${NC}"
            
            if [ -f "${SECURE_VAULT}/talosconfig-latest" ]; then
                mkdir -p talos
                cp "${SECURE_VAULT}/talosconfig-latest" talos/talosconfig
                export TALOSCONFIG="$(pwd)/talos/talosconfig"
                echo -e "${GREEN}✓ Copied talosconfig from vault${NC}"
            fi
        else
            echo -e "${YELLOW}Please retrieve secrets manually${NC}"
            echo ""
            echo "Required files:"
            echo "  1. secrets.yaml → $(pwd)/secrets.yaml"
            echo "  2. talosconfig → $(pwd)/talos/talosconfig"
            echo ""
            echo "Press Enter when secrets are in place..."
            read -r
        fi
    else
        echo -e "${YELLOW}⚠️  Local vault not found: ${SECURE_VAULT}${NC}"
        echo ""
        echo -e "${YELLOW}Please retrieve secrets manually and place them:${NC}"
        echo "  1. secrets.yaml → $(pwd)/secrets.yaml"
        echo "  2. talosconfig → $(pwd)/talos/talosconfig"
        echo ""
        echo "Then press Enter to continue..."
        read -r
    fi
    
    # Verify secrets are now present
    if [ ! -f "./secrets.yaml" ]; then
        echo -e "${RED}✗ secrets.yaml still not found${NC}"
        echo -e "${RED}Cannot proceed without secrets${NC}"
        echo ""
        echo "Options:"
        echo "  1. Retrieve secrets from vault and place in $(pwd)/secrets.yaml"
        echo "  2. Generate new secrets (loses cluster identity)"
        echo ""
        rm -rf "${TEMP_DIR}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Secrets verified${NC}"
fi

# Restore node configs (these should always be in backup)
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
if [ "$SECRETS_IN_BACKUP" = true ]; then
    echo "  ✓ Talos secrets (from backup)"
else
    echo "  ✓ Talos secrets (from secure vault)"
fi
echo "  ✓ Talos configs"
[ -f "kubeconfig" ] && echo "  ✓ kubeconfig"
[ "$RESTORE_ETCD" = "yes" ] && echo "  ✓ etcd snapshot"
[ "$RESTORE_K8S" = "yes" ] && echo "  ✓ Kubernetes resources"
echo ""
echo "Secret source:"
if [ "$SECRETS_IN_BACKUP" = true ]; then
    echo "  • Secrets were included in backup archive"
else
    echo "  • Secrets retrieved from secure vault"
    echo "  • Backup did NOT contain secrets (secure configuration)"
fi
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
if [ "$SECRETS_IN_BACKUP" = false ]; then
    echo "  4. Verify Flux secrets (if using Flux):"
    echo "     kubectl get secrets -n flux-system"
    echo "     # If missing, restore from vault:"
    echo "     kubectl apply -f ~/secure-vault/cluster-secrets/flux-secrets-latest.yaml"
    echo ""
fi
echo "  5. Review logs if issues occur:"
echo "     talosctl --nodes 192.168.99.101 logs kubelet"
echo "     kubectl logs -n kube-system <pod-name>"
echo ""
if [ "$SECRETS_IN_BACKUP" = false ]; then
    echo -e "${GREEN}✓ Secure Configuration Detected${NC}"
    echo "  Your backup followed security best practices by"
    echo "  excluding secrets. They were safely stored separately."
    echo ""
fi
echo "========================================="

exit 0