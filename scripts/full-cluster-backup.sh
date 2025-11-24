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

# Prompt for secret inclusion
echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Secret Handling Configuration${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "\n${YELLOW}Include secrets in this backup?${NC}"
echo -e "${GREEN}Recommended: NO${NC} (store secrets separately for security)"
echo -e "\nSecrets that would be included:"
echo -e "  • secrets.yaml (Talos cluster PKI)"
echo -e "  • talosconfig (Talos API credentials)"
echo -e "  • flux-secrets.yaml (Git repository access)"
echo -e "\n${YELLOW}Your choice (yes/no):${NC} "
read -r INCLUDE_SECRETS

if [ "$INCLUDE_SECRETS" != "yes" ]; then
    INCLUDE_SECRETS="no"
    echo -e "${GREEN}✓ Secrets will be EXCLUDED (recommended for security)${NC}"
    echo -e "${YELLOW}⚠️  Remember: Secrets should be backed up separately!${NC}"
    echo -e "${YELLOW}   Run: ./scripts/backup-secrets-only.sh${NC}"
else
    echo -e "${YELLOW}⚠️  Secrets will be INCLUDED in this backup${NC}"
    echo -e "${RED}⚠️  CRITICAL: You MUST encrypt this backup archive!${NC}"
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

sleep 2  # Give user time to read

# 1. Backup Talos configuration
echo -e "\n${BLUE}[1/5]${NC} Backing up Talos configuration..."

if [ "$INCLUDE_SECRETS" = "yes" ]; then
    # Include secrets in backup
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
else
    # Exclude secrets - create reminder file
    echo -e "${YELLOW}⚠ secrets.yaml EXCLUDED (recommended)${NC}"
    echo -e "${YELLOW}⚠ talosconfig EXCLUDED (recommended)${NC}"
    
    cat > "${BACKUP_DIR}/talos/SECRETS_NOT_INCLUDED.txt" <<'EOFREMINDER'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  SECRETS NOT INCLUDED IN THIS BACKUP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This backup was created WITHOUT secrets for security reasons.

REQUIRED FOR FULL RESTORE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. secrets.yaml      - Talos cluster PKI and secrets
2. talosconfig       - Talos API access credentials
3. flux-secrets.yaml - Git repository access (optional)

WHERE TO FIND SECRETS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Check your secure vault (select one):
[ ] 1Password vault "Cluster Secrets"
[ ] Encrypted USB drive (in safe)
[ ] S3 bucket: s3://YOUR-COMPANY-cluster-secrets
[ ] Other secure location: _______________________

BACKUP SECRETS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Run: ./scripts/backup-secrets-only.sh

RESTORE PROCEDURES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
See: docs/DISASTER_RECOVERY_PHILOSOPHY.md
     docs/SECRET_SEPARATION_ACTION_PLAN.md

ALTERNATIVE RECOVERY:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Without secrets, you can still recover by:
1. Generating new Talos secrets
2. Re-bootstrapping Flux with new credentials
3. Restoring applications from Git

Note: You will LOSE cluster identity and etcd history.
EOFREMINDER
    
    echo -e "${GREEN}✓ Created SECRETS_NOT_INCLUDED.txt reminder${NC}"
fi

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
    
    # Handle Flux secrets based on user preference
    if [ "$INCLUDE_SECRETS" = "yes" ]; then
        kubectl get secrets -n flux-system -o yaml > \
            "${BACKUP_DIR}/flux/flux-secrets.yaml" 2>/dev/null && \
            echo -e "${GREEN}✓ Flux secrets${NC}" || \
            echo -e "${YELLOW}⚠ Flux secrets not found${NC}"
    else
        echo -e "${YELLOW}⚠ Flux secrets EXCLUDED (recommended)${NC}"
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

if [ "$INCLUDE_SECRETS" = "yes" ]; then
    SECRET_STATUS="INCLUDED (⚠️  ENCRYPT THIS ARCHIVE!)"
else
    SECRET_STATUS="EXCLUDED (stored separately)"
fi

cat > "${BACKUP_DIR}/MANIFEST.txt" <<EOF
========================================
Cluster Backup Manifest
========================================
Backup Time: ${TIMESTAMP}
Cluster: talos-cluster
Backup Type: Full Cluster Backup
Secrets: ${SECRET_STATUS}

Control Plane Nodes:
  - 192.168.99.101 (controlplane-01)
  - 192.168.99.102 (controlplane-02)
  - 192.168.99.103 (controlplane-03)

Worker Nodes:
  - 192.168.99.111 (worker-01)

Contents:
========================================
talos/
EOF

if [ "$INCLUDE_SECRETS" = "yes" ]; then
    cat >> "${BACKUP_DIR}/MANIFEST.txt" <<'EOF'
  ├── secrets.yaml        ⚠️  Critical cluster secrets (SENSITIVE)
  ├── talosconfig         ⚠️  Talos API credentials (SENSITIVE)
EOF
else
    cat >> "${BACKUP_DIR}/MANIFEST.txt" <<'EOF'
  ├── SECRETS_NOT_INCLUDED.txt  (secrets stored separately)
EOF
fi

cat >> "${BACKUP_DIR}/MANIFEST.txt" <<'EOF'
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
EOF

if [ "$INCLUDE_SECRETS" = "yes" ]; then
    cat >> "${BACKUP_DIR}/MANIFEST.txt" <<'EOF'
  ├── flux-secrets.yaml   ⚠️  Git credentials (SENSITIVE)
EOF
fi

cat >> "${BACKUP_DIR}/MANIFEST.txt" <<'EOF'
  └── flux/              Flux manifests

kubeconfig               Kubernetes API credentials

Restore Procedure:
========================================
EOF

if [ "$INCLUDE_SECRETS" = "yes" ]; then
    cat >> "${BACKUP_DIR}/MANIFEST.txt" <<EOF
⚠️  THIS BACKUP CONTAINS SECRETS - HANDLE SECURELY! ⚠️

1. Extract backup archive
2. Restore Talos cluster using included secrets.yaml
3. Bootstrap cluster
4. Restore etcd from snapshot
5. Apply Kubernetes manifests
6. Apply Flux secrets and resources

SECURITY NOTICE:
- This archive contains sensitive secrets
- Encrypt before uploading to cloud storage
- Store in secure location with restricted access
- Delete unencrypted copies after secure storage
EOF
else
    cat >> "${BACKUP_DIR}/MANIFEST.txt" <<EOF
This backup does NOT contain secrets (recommended for security).

For full restore, you will also need:
1. secrets.yaml (from secure vault)
2. talosconfig (from secure vault)
3. flux-secrets.yaml (from secure vault)

Restore steps:
1. Retrieve secrets from secure vault
2. Extract this backup archive
3. Copy secrets to appropriate locations
4. Run: ./scripts/restore-cluster.sh
5. Cluster will restore with original identity

Alternative (without secrets):
1. Generate new Talos secrets
2. Build new cluster from scratch
3. Flux recreates apps from Git
Note: Loses cluster identity and etcd history
EOF
fi

cat >> "${BACKUP_DIR}/MANIFEST.txt" <<EOF

For detailed instructions, see:
  docs/BACKUP_GUIDE.md
  docs/DISASTER_RECOVERY_PHILOSOPHY.md

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

if [ "$INCLUDE_SECRETS" = "yes" ]; then
    echo -e "Secrets: ${RED}INCLUDED${NC} ⚠️"
    echo ""
    echo -e "${RED}⚠️  CRITICAL SECURITY NOTICE:${NC}"
    echo -e "${YELLOW}This backup contains sensitive secrets!${NC}"
    echo ""
    echo "Required actions:"
    echo "  1. Encrypt this archive immediately"
    echo "  2. Store in secure location with restricted access"
    echo "  3. Never upload unencrypted to cloud storage"
    echo "  4. Delete unencrypted copies after secure storage"
    echo ""
    echo "Encrypt command:"
    echo "  gpg --encrypt --recipient your@email.com \\"
    echo "    ${BACKUP_ROOT}/${ARCHIVE_NAME}"
else
    echo -e "Secrets: ${GREEN}EXCLUDED${NC} ✓ (recommended)"
    echo ""
    echo -e "${GREEN}✓ This backup is safe for standard storage${NC}"
    echo ""
    echo "Note: For full restore, you'll need secrets from:"
    echo "  • 1Password vault 'Cluster Secrets' OR"
    echo "  • Encrypted USB drive OR"
    echo "  • Separate secure S3 bucket"
    echo ""
    echo "Backup secrets separately with:"
    echo "  ./scripts/backup-secrets-only.sh"
fi

echo ""
echo "Details: See MANIFEST.txt in archive"
echo "========================================="

exit 0