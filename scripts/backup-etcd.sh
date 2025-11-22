#!/bin/bash
# Automated etcd backup script for Talos Kubernetes cluster
# This script creates daily etcd snapshots and manages retention
# Run from project root directory

set -e

# Get script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
BACKUP_DIR="${HOME}/cluster-backups/etcd"
RETENTION_DAYS=30
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_NAME="etcd-snapshot-${TIMESTAMP}.db"
CONTROL_PLANE_IP="192.168.99.101"

# Set talosconfig path (talosconfig is in talos/ directory)
export TALOSCONFIG="${PROJECT_ROOT}/talos/talosconfig"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "etcd Backup Script"
echo "Timestamp: ${TIMESTAMP}"
echo "========================================="

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Check if talosctl is available
if ! command -v talosctl &> /dev/null; then
    echo -e "${RED}✗ talosctl not found. Please install it first.${NC}"
    exit 1
fi

# Check if control plane is reachable
echo -e "\n${YELLOW}Checking control plane connectivity...${NC}"
if ! talosctl --nodes ${CONTROL_PLANE_IP} version &> /dev/null; then
    echo -e "${RED}✗ Cannot reach control plane at ${CONTROL_PLANE_IP}${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Control plane is reachable${NC}"

# Create etcd snapshot - talosctl can save directly to local path
echo -e "\n${YELLOW}Creating etcd snapshot...${NC}"
if talosctl --nodes ${CONTROL_PLANE_IP} etcd snapshot "${BACKUP_DIR}/${SNAPSHOT_NAME}"; then
    echo -e "${GREEN}✓ etcd snapshot created${NC}"
else
    echo -e "${RED}✗ Failed to create etcd snapshot${NC}"
    exit 1
fi

# Verify snapshot exists and has size
if [ -f "${BACKUP_DIR}/${SNAPSHOT_NAME}" ]; then
    SNAPSHOT_SIZE=$(du -h "${BACKUP_DIR}/${SNAPSHOT_NAME}" | cut -f1)
    echo -e "${GREEN}✓ Backup verified${NC}"
    echo -e "  Size: ${SNAPSHOT_SIZE}"
else
    echo -e "${RED}✗ Backup file not found!${NC}"
    exit 1
fi

# Delete old backups
echo -e "\n${YELLOW}Cleaning up old backups (older than ${RETENTION_DAYS} days)...${NC}"
DELETED_COUNT=$(find "${BACKUP_DIR}" -name "etcd-snapshot-*.db" -mtime +${RETENTION_DAYS} -delete -print | wc -l)
if [ "${DELETED_COUNT}" -gt 0 ]; then
    echo -e "${GREEN}✓ Deleted ${DELETED_COUNT} old backup(s)${NC}"
else
    echo "  No old backups to delete"
fi

# Show current backups
echo -e "\n${YELLOW}Current backups:${NC}"
BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/etcd-snapshot-*.db 2>/dev/null | wc -l)
echo "  Total backups: ${BACKUP_COUNT}"
echo "  Newest 5:"
ls -lht "${BACKUP_DIR}"/etcd-snapshot-*.db 2>/dev/null | head -5 | awk '{print "    " $9 " (" $5 ")"}'

# Optional: Upload to cloud storage (uncomment and configure)
# if command -v aws &> /dev/null; then
#     echo -e "\n${YELLOW}Uploading to S3...${NC}"
#     if aws s3 cp "${BACKUP_DIR}/${SNAPSHOT_NAME}" \
#         s3://your-bucket/etcd-backups/ --sse AES256; then
#         echo -e "${GREEN}✓ Uploaded to S3${NC}"
#     else
#         echo -e "${RED}✗ S3 upload failed${NC}"
#     fi
# fi

echo -e "\n========================================="
echo -e "${GREEN}Backup completed successfully!${NC}"
echo "Location: ${BACKUP_DIR}/${SNAPSHOT_NAME}"
echo "========================================="

exit 0