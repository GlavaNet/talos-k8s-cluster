#!/bin/bash
# Full cluster backup script for Talos Kubernetes cluster
# Backs up: Talos configs, etcd, Kubernetes resources, and kubeconfig
# Run from project root directory

set -e

# Get script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
BACKUP_ROOT="${HOME}/cluster-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
CONTROL_PLANE_IP="192.168.99.101"
RETENTION_DAYS=14

# Set talosconfig and kubeconfig paths
export TALOSCONFIG="${PROJECT_ROOT}/talos/talosconfig"
export KUBECONFIG="${PROJECT_ROOT}/kubeconfig"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================="
echo "Full Cluster Backup"
echo "Timestamp: ${TIMESTAMP}"
echo "========================================="

# Create backup directory structure
mkdir -p "${BACKUP_DIR}"/{talos,etcd,kubernetes,flux}

# Check prerequisites
echo -e "\n${BLUE}[Prerequisites]${NC} Checking tools..."
MISSING_TOOLS=0

if ! command -v talosctl &> /dev/null; then
    echo -e "${RED}✗ talosctl not found${NC}"
    MISSING_TOOLS=1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    MISSING_TOOLS=1
fi

if [ ${MISSING_TOOLS} -eq 1 ]; then
    echo -e "${RED}Please install missing tools before continuing${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All required tools found${NC}"

# 1. Backup Talos configuration
echo -e "\n${BLUE}[1/5]${NC} Backing up Talos configuration..."

# Check for secrets.yaml in root directory
if [ ! -f "${PROJECT_ROOT}/secrets.yaml" ]; then
    echo -e "${RED}✗ secrets.yaml not found in root directory!${NC}"
    echo "  This is critical for cluster recovery"
    exit 1
fi

cp "${PROJECT_ROOT}/secrets.yaml" "${BACKUP_DIR}/talos/" 2>/dev/null && \
    echo -e "${GREEN}✓ secrets.yaml${NC}" || \
    echo -e "${RED}✗ secrets.yaml${NC}"

cp "${PROJECT_ROOT}/talos/talosconfig" "${BACKUP_DIR}/talos/" 2>/dev/null && \
    echo -e "${GREEN}✓ talosconfig${NC}" || \
    echo -e "${YELLOW}⚠ talosconfig not found${NC}"

cp -r "${PROJECT_ROOT}/talos/controlplane/" "${BACKUP_DIR}/talos/" 2>/dev/null && \
    echo -e "${GREEN}✓ controlplane configs${NC}" || \
    echo -e "${YELLOW}⚠ controlplane configs not found${NC}"

cp -r "${PROJECT_ROOT}/talos/worker/" "${BACKUP_DIR}/talos/" 2>/dev/null && \
    echo -e "${GREEN}✓ worker configs${NC}" || \
    echo -e "${YELLOW}⚠ worker configs not found${NC}"

# 2. Backup etcd
echo -e "\n${BLUE}[2/5]${NC} Backing up etcd..."

if talosctl --nodes ${CONTROL_PLANE_IP} version &> /dev/null; then
    # talosctl etcd snapshot can save directly to a local file path
    echo -e "  Creating etcd snapshot..."
    
    # Save snapshot directly to backup directory
    if talosctl --nodes ${CONTROL_PLANE_IP} etcd snapshot "${BACKUP_DIR}/etcd/snapshot.db"; then
        
        # Verify the file was created and has content
        if [ -f "${BACKUP_DIR}/etcd/snapshot.db" ] && [ -s "${BACKUP_DIR}/etcd/snapshot.db" ]; then
            ETCD_SIZE=$(du -h "${BACKUP_DIR}/etcd/snapshot.db" | cut -f1)
            echo -e "${GREEN}✓ etcd snapshot (${ETCD_SIZE})${NC}"
        else
            echo -e "${RED}✗ etcd snapshot file is missing or empty${NC}"
        fi
    else
        echo -e "${RED}✗ etcd snapshot command failed${NC}"
        echo -e "${YELLOW}  Note: Snapshot may have been created on node at /tmp/etcd-snapshot.db${NC}"
    fi
else
    echo -e "${RED}✗ Cannot reach control plane at ${CONTROL_PLANE_IP}${NC}"
    echo "  Skipping etcd backup"
fi

# 3. Backup Kubernetes resources
echo -e "\n${BLUE}[3/5]${NC} Backing up Kubernetes resources..."

if kubectl cluster-info &> /dev/null; then
    # All resources
    kubectl get all --all-namespaces -o yaml > "${BACKUP_DIR}/kubernetes/all-resources.yaml" 2>/dev/null && \
        echo -e "${GREEN}✓ All resources${NC}" || \
        echo -e "${RED}✗ All resources${NC}"
    
    # Persistent volumes
    kubectl get pv,pvc --all-namespaces -o yaml > "${BACKUP_DIR}/kubernetes/volumes.yaml" 2>/dev/null && \
        echo -e "${GREEN}✓ Persistent volumes${NC}" || \
        echo -e "${RED}✗ Persistent volumes${NC}"
    
    # ConfigMaps and Secrets
    kubectl get configmap,secret --all-namespaces -o yaml > "${BACKUP_DIR}/kubernetes/configs.yaml" 2>/dev/null && \
        echo -e "${GREEN}✓ ConfigMaps and Secrets${NC}" || \
        echo -e "${RED}✗ ConfigMaps and Secrets${NC}"
    
    # CRDs
    kubectl get crd -o yaml > "${BACKUP_DIR}/kubernetes/crds.yaml" 2>/dev/null && \
        echo -e "${GREEN}✓ Custom Resource Definitions${NC}" || \
        echo -e "${YELLOW}⚠ No CRDs found${NC}"
    
    # Ingresses
    kubectl get ingress --all-namespaces -o yaml > "${BACKUP_DIR}/kubernetes/ingresses.yaml" 2>/dev/null && \
        echo -e "${GREEN}✓ Ingresses${NC}" || \
        echo -e "${YELLOW}⚠ No Ingresses found${NC}"
    
    # Storage Classes
    kubectl get storageclass -o yaml > "${BACKUP_DIR}/kubernetes/storageclasses.yaml" 2>/dev/null && \
        echo -e "${GREEN}✓ Storage Classes${NC}" || \
        echo -e "${RED}✗ Storage Classes${NC}"
else
    echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
    echo "  Skipping Kubernetes backup"
fi

# 4. Backup Flux configuration (if present)
echo -e "\n${BLUE}[4/5]${NC} Backing up Flux configuration..."

if kubectl get namespace flux-system &> /dev/null; then
    kubectl get gitrepository,kustomization,helmrepository,helmrelease \
        -n flux-system -o yaml > "${BACKUP_DIR}/flux/flux-resources.yaml" 2>/dev/null && \
        echo -e "${GREEN}✓ Flux resources${NC}" || \
        echo -e "${RED}✗ Flux resources${NC}"
    
    # Copy local Flux manifests if they exist
    if [ -d "${PROJECT_ROOT}/kubernetes/flux" ]; then
        cp -r "${PROJECT_ROOT}/kubernetes/flux" "${BACKUP_DIR}/" && \
            echo -e "${GREEN}✓ Flux manifests${NC}" || \
            echo -e "${YELLOW}⚠ Flux manifests${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Flux not installed${NC}"
fi

# 5. Backup kubeconfig
echo -e "\n${BLUE}[5/5]${NC} Backing up kubeconfig..."

if [ -f "${PROJECT_ROOT}/kubeconfig" ]; then
    cp "${PROJECT_ROOT}/kubeconfig" "${BACKUP_DIR}/" && \
        echo -e "${GREEN}✓ kubeconfig${NC}" || \
        echo -e "${RED}✗ kubeconfig${NC}"
elif [ -f "${HOME}/.kube/config" ]; then
    cp "${HOME}/.kube/config" "${BACKUP_DIR}/kubeconfig" && \
        echo -e "${GREEN}✓ kubeconfig (from ~/.kube/config)${NC}" || \
        echo -e "${RED}✗ kubeconfig${NC}"
else
    echo -e "${YELLOW}⚠ kubeconfig not found${NC}"
fi

# Create manifest file
echo -e "\n${YELLOW}Creating backup manifest...${NC}"
cat > "${BACKUP_DIR}/MANIFEST.txt" <<EOF
========================================
Cluster Backup Manifest
========================================
Backup Time: ${TIMESTAMP}
Cluster Name: talos-cluster
Backup Type: Full Cluster Backup

Control Plane Nodes:
  - 192.168.99.101 (controlplane-01)
  - 192.168.99.102 (controlplane-02)
  - 192.168.99.103 (controlplane-03)

Worker Nodes:
  - 192.168.99.111 (worker-01)

Contents:
========================================
talos/
  ├── secrets.yaml        Critical cluster secrets
  ├── talosconfig         Talos API credentials
  ├── controlplane/       Control plane configs
  └── worker/             Worker configs

etcd/
  └── snapshot.db         etcd database snapshot

kubernetes/
  ├── all-resources.yaml  All K8s resources
  ├── volumes.yaml        PVs and PVCs
  ├── configs.yaml        ConfigMaps and Secrets
  ├── crds.yaml          Custom Resource Definitions
  ├── ingresses.yaml     Ingress resources
  └── storageclasses.yaml Storage Classes

flux/
  ├── flux-resources.yaml Flux GitOps resources
  └── flux/              Flux manifests

kubeconfig               Kubernetes API credentials

Restore Procedure:
========================================
1. Extract this backup archive
2. Flash new SD cards with Talos images
3. Copy talos/secrets.yaml back to project
4. Apply node configurations
5. Bootstrap cluster
6. Restore etcd if needed
7. Apply Kubernetes resources
8. Verify cluster health

For detailed instructions, see:
  BACKUP_GUIDE.md

========================================
Generated by: full-cluster-backup.sh
========================================
EOF

echo -e "${GREEN}✓ Manifest created${NC}"

# Create compressed archive
echo -e "\n${YELLOW}Creating compressed archive...${NC}"
ARCHIVE_NAME="cluster-backup-${TIMESTAMP}.tar.gz"
tar czf "${BACKUP_ROOT}/${ARCHIVE_NAME}" \
    -C "${BACKUP_ROOT}" "${TIMESTAMP}" 2>&1 | grep -v "Removing leading"

if [ -f "${BACKUP_ROOT}/${ARCHIVE_NAME}" ]; then
    ARCHIVE_SIZE=$(du -h "${BACKUP_ROOT}/${ARCHIVE_NAME}" | cut -f1)
    echo -e "${GREEN}✓ Archive created (${ARCHIVE_SIZE})${NC}"
    
    # Cleanup uncompressed directory
    rm -rf "${BACKUP_DIR}"
else
    echo -e "${RED}✗ Failed to create archive${NC}"
    exit 1
fi

# Clean old backups
echo -e "\n${YELLOW}Cleaning up old backups (older than ${RETENTION_DAYS} days)...${NC}"
DELETED_COUNT=$(find "${BACKUP_ROOT}" -name "cluster-backup-*.tar.gz" -mtime +${RETENTION_DAYS} -delete -print | wc -l)
if [ "${DELETED_COUNT}" -gt 0 ]; then
    echo -e "${GREEN}✓ Deleted ${DELETED_COUNT} old backup(s)${NC}"
else
    echo "  No old backups to delete"
fi

# Show current backups
echo -e "\n${YELLOW}Current backups:${NC}"
BACKUP_COUNT=$(ls -1 "${BACKUP_ROOT}"/cluster-backup-*.tar.gz 2>/dev/null | wc -l)
echo "  Total backups: ${BACKUP_COUNT}"
echo "  Newest 5:"
ls -lht "${BACKUP_ROOT}"/cluster-backup-*.tar.gz 2>/dev/null | head -5 | awk '{print "    " $9 " (" $5 ")"}'

# Optional: Upload to cloud storage (uncomment and configure)
# echo -e "\n${YELLOW}Uploading to cloud storage...${NC}"
# if command -v aws &> /dev/null; then
#     if aws s3 cp "${BACKUP_ROOT}/${ARCHIVE_NAME}" \
#         s3://your-bucket/cluster-backups/ --sse AES256; then
#         echo -e "${GREEN}✓ Uploaded to S3${NC}"
#     else
#         echo -e "${RED}✗ S3 upload failed${NC}"
#     fi
# fi

# Summary
echo -e "\n========================================="
echo -e "${GREEN}Backup completed successfully!${NC}"
echo "========================================="
echo "Archive: ${BACKUP_ROOT}/${ARCHIVE_NAME}"
echo "Size: ${ARCHIVE_SIZE}"
echo "Contents: See ${ARCHIVE_NAME%%.tar.gz}/MANIFEST.txt"
echo "========================================="

exit 0