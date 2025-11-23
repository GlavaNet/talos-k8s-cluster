#!/bin/bash
# Setup script for cluster backup system
# This script installs and configures the backup infrastructure

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "Cluster Backup System Setup"
echo "========================================="

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "\n${BLUE}Project root: ${PROJECT_ROOT}${NC}"

# 1. Check prerequisites
echo -e "\n${BLUE}[1/5]${NC} Checking prerequisites..."

MISSING_TOOLS=0

if ! command -v talosctl &> /dev/null; then
    echo -e "${RED}✗ talosctl not found${NC}"
    echo "  Install: https://www.talos.dev/latest/introduction/getting-started/"
    MISSING_TOOLS=1
else
    echo -e "${GREEN}✓ talosctl${NC}"
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    echo "  Install: https://kubernetes.io/docs/tasks/tools/"
    MISSING_TOOLS=1
else
    echo -e "${GREEN}✓ kubectl${NC}"
fi

if [ ${MISSING_TOOLS} -eq 1 ]; then
    echo -e "\n${RED}Please install missing tools before continuing${NC}"
    exit 1
fi

# Optional tools
if command -v flux &> /dev/null; then
    echo -e "${GREEN}✓ flux${NC}"
else
    echo -e "${YELLOW}⚠ flux not found (optional)${NC}"
fi

if command -v aws &> /dev/null; then
    echo -e "${GREEN}✓ aws-cli${NC}"
else
    echo -e "${YELLOW}⚠ aws-cli not found (optional, for S3 uploads)${NC}"
fi

# 2. Create backup directory structure
echo -e "\n${BLUE}[2/5]${NC} Creating backup directory structure..."

BACKUP_ROOT="${HOME}/cluster-backups"
mkdir -p "${BACKUP_ROOT}"/{etcd,talos-secrets,velero}

echo -e "${GREEN}✓ Created ${BACKUP_ROOT}${NC}"
tree -L 1 "${BACKUP_ROOT}" 2>/dev/null || ls -la "${BACKUP_ROOT}"

# 3. Copy scripts to project
echo -e "\n${BLUE}[3/5]${NC} Installing backup scripts..."

if [ ! -d "${PROJECT_ROOT}/scripts" ]; then
    mkdir -p "${PROJECT_ROOT}/scripts"
fi

# Copy backup scripts
for script in backup-etcd.sh full-cluster-backup.sh; do
    if [ -f "${script}" ]; then
        cp "${script}" "${PROJECT_ROOT}/scripts/"
        chmod +x "${PROJECT_ROOT}/scripts/${script}"
        echo -e "${GREEN}✓ Installed ${script}${NC}"
    fi
done

# Copy backup guide
if [ -f "BACKUP_GUIDE.md" ]; then
    cp BACKUP_GUIDE.md "${PROJECT_ROOT}/docs/"
    echo -e "${GREEN}✓ Installed BACKUP_GUIDE.md${NC}"
fi

# 4. Create initial backup of Talos secrets
echo -e "\n${BLUE}[4/5]${NC} Backing up Talos secrets..."

if [ -f "${PROJECT_ROOT}/secrets.yaml" ]; then
    TIMESTAMP=$(date +%Y%m%d)
    cp "${PROJECT_ROOT}/secrets.yaml" \
       "${BACKUP_ROOT}/talos-secrets/secrets-${TIMESTAMP}.yaml"
    echo -e "${GREEN}✓ Secrets backed up to ${BACKUP_ROOT}/talos-secrets/${NC}"
    
    # Set restrictive permissions
    chmod 600 "${BACKUP_ROOT}/talos-secrets/secrets-${TIMESTAMP}.yaml"
    echo -e "${GREEN}✓ Permissions set to 600${NC}"
else
    echo -e "${YELLOW}⚠ secrets.yaml not found in root directory${NC}"
    echo "  You'll need to back this up manually after cluster creation"
fi

# 5. Set up cron jobs (optional)
echo -e "\n${BLUE}[5/5]${NC} Configuring automated backups..."

echo -e "\n${YELLOW}Would you like to set up automated daily backups? (y/n)${NC}"
read -r SETUP_CRON

if [[ "$SETUP_CRON" =~ ^[Yy]$ ]]; then
    # Create cron entries
    CRON_ETCD="0 2 * * * ${PROJECT_ROOT}/scripts/backup-etcd.sh >> /var/log/etcd-backup.log 2>&1"
    CRON_FULL="0 1 * * 0 ${PROJECT_ROOT}/scripts/full-cluster-backup.sh >> /var/log/cluster-backup.log 2>&1"
    
    # Check if cron entries already exist
    if crontab -l 2>/dev/null | grep -q "backup-etcd.sh"; then
        echo -e "${YELLOW}⚠ Cron jobs already exist${NC}"
    else
        # Add cron jobs
        (crontab -l 2>/dev/null; echo "# Talos cluster backups"; echo "$CRON_ETCD"; echo "$CRON_FULL") | crontab -
        echo -e "${GREEN}✓ Cron jobs added${NC}"
        echo "  - Daily etcd backup: 2:00 AM"
        echo "  - Weekly full backup: 1:00 AM Sunday"
    fi
else
    echo -e "${YELLOW}⚠ Skipping cron setup${NC}"
    echo "  You can manually run backups with:"
    echo "    ${PROJECT_ROOT}/scripts/backup-etcd.sh"
    echo "    ${PROJECT_ROOT}/scripts/full-cluster-backup.sh"
fi

# Display current cron jobs
echo -e "\n${YELLOW}Current backup cron jobs:${NC}"
crontab -l 2>/dev/null | grep -E "backup-(etcd|cluster)" || echo "  None configured"

# Create README in backup directory
cat > "${BACKUP_ROOT}/README.txt" <<EOF
Talos Cluster Backups
=====================

This directory contains automated backups of your Talos Kubernetes cluster.

Directory Structure:
-------------------
etcd/           - Daily etcd snapshots (30 day retention)
talos-secrets/  - Critical Talos secrets (NEVER DELETE)
velero/         - Velero application backups (if configured)

Backup Scripts:
--------------
${PROJECT_ROOT}/scripts/backup-etcd.sh         - Daily etcd backup
${PROJECT_ROOT}/scripts/full-cluster-backup.sh - Full cluster backup

Manual Backup:
-------------
cd ${PROJECT_ROOT}
./scripts/full-cluster-backup.sh

Restore:
-------
See ${PROJECT_ROOT}/docs/BACKUP_GUIDE.md for detailed restore procedures

Important Notes:
---------------
⚠️  NEVER delete talos-secrets/ - these are required for cluster recovery
⚠️  Test your backups regularly
⚠️  Keep off-site copies of critical backups
⚠️  Encrypt backups before uploading to cloud storage

Generated: $(date)
EOF

# Summary
echo -e "\n========================================="
echo -e "${GREEN}Backup System Setup Complete!${NC}"
echo "========================================="
echo ""
echo "Backup directory: ${BACKUP_ROOT}"
echo "Scripts installed: ${PROJECT_ROOT}/scripts/"
echo "Documentation: ${PROJEC#!/bin/bash
# Setup script for cluster backup system
# This script installs and configures the backup infrastructure

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "Cluster Backup System Setup"
echo "========================================="

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "\n${BLUE}Project root: ${PROJECT_ROOT}${NC}"

# 1. Check prerequisites
echo -e "\n${BLUE}[1/5]${NC} Checking prerequisites..."

MISSING_TOOLS=0

if ! command -v talosctl &> /dev/null; then
    echo -e "${RED}✗ talosctl not found${NC}"
    echo "  Install: https://www.talos.dev/latest/introduction/getting-started/"
    MISSING_TOOLS=1
else
    echo -e "${GREEN}✓ talosctl${NC}"
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    echo "  Install: https://kubernetes.io/docs/tasks/tools/"
    MISSING_TOOLS=1
else
    echo -e "${GREEN}✓ kubectl${NC}"
fi

if [ ${MISSING_TOOLS} -eq 1 ]; then
    echo -e "\n${RED}Please install missing tools before continuing${NC}"
    exit 1
fi

# Optional tools
if command -v flux &> /dev/null; then
    echo -e "${GREEN}✓ flux${NC}"
else
    echo -e "${YELLOW}⚠ flux not found (optional)${NC}"
fi

if command -v aws &> /dev/null; then
    echo -e "${GREEN}✓ aws-cli${NC}"
else
    echo -e "${YELLOW}⚠ aws-cli not found (optional, for S3 uploads)${NC}"
fi

# 2. Create backup directory structure
echo -e "\n${BLUE}[2/5]${NC} Creating backup directory structure..."

BACKUP_ROOT="${HOME}/cluster-backups"
mkdir -p "${BACKUP_ROOT}"/{etcd,talos-secrets,velero}

echo -e "${GREEN}✓ Created ${BACKUP_ROOT}${NC}"
tree -L 1 "${BACKUP_ROOT}" 2>/dev/null || ls -la "${BACKUP_ROOT}"

# 3. Copy scripts to project
echo -e "\n${BLUE}[3/5]${NC} Installing backup scripts..."

if [ ! -d "${PROJECT_ROOT}/scripts" ]; then
    mkdir -p "${PROJECT_ROOT}/scripts"
fi

# Copy backup scripts
for script in backup-etcd.sh full-cluster-backup.sh; do
    if [ -f "${script}" ]; then
        cp "${script}" "${PROJECT_ROOT}/scripts/"
        chmod +x "${PROJECT_ROOT}/scripts/${script}"
        echo -e "${GREEN}✓ Installed ${script}${NC}"
    fi
done

# Copy backup guide
if [ -f "BACKUP_GUIDE.md" ]; then
    cp BACKUP_GUIDE.md "${PROJECT_ROOT}/docs/"
    echo -e "${GREEN}✓ Installed BACKUP_GUIDE.md${NC}"
fi

# 4. Set up secure vault and backup initial secrets
echo -e "\n${BLUE}[4/5]${NC} Setting up secure secret vault..."

# Create secure vault (separate from regular backups)
SECURE_VAULT="${HOME}/secure-vault/cluster-secrets"
mkdir -p "${SECURE_VAULT}"
chmod 700 "${SECURE_VAULT}"

echo -e "${GREEN}✓ Secure vault created: ${SECURE_VAULT}${NC}"

# Ask user if they want to backup secrets now
echo -e "\n${YELLOW}Backup secrets to secure vault now? (y/n)${NC}"
echo "  Recommended: yes"
echo "  Location: ${SECURE_VAULT}"
read -r BACKUP_SECRETS_NOW

if [[ "$BACKUP_SECRETS_NOW" =~ ^[Yy]$ ]]; then
    if [ -f "${PROJECT_ROOT}/secrets.yaml" ]; then
        TIMESTAMP=$(date +%Y%m%d)
        cp "${PROJECT_ROOT}/secrets.yaml" \
           "${SECURE_VAULT}/secrets-${TIMESTAMP}.yaml"
        ln -sf "secrets-${TIMESTAMP}.yaml" \
           "${SECURE_VAULT}/secrets-latest.yaml"
        chmod 600 "${SECURE_VAULT}/secrets-"*.yaml
        echo -e "${GREEN}✓ secrets.yaml backed up to secure vault${NC}"
    else
        echo -e "${YELLOW}⚠ secrets.yaml not found in root directory${NC}"
        echo "  You'll need to back this up after cluster creation"
    fi
    
    if [ -f "${PROJECT_ROOT}/talos/talosconfig" ]; then
        cp "${PROJECT_ROOT}/talos/talosconfig" \
           "${SECURE_VAULT}/talosconfig-${TIMESTAMP}"
        ln -sf "talosconfig-${TIMESTAMP}" \
           "${SECURE_VAULT}/talosconfig-latest"
        chmod 600 "${SECURE_VAULT}/talosconfig-"*
        echo -e "${GREEN}✓ talosconfig backed up to secure vault${NC}"
    fi
    
    echo -e "\n${GREEN}✓ Secrets backed up to secure vault${NC}"
    echo -e "${YELLOW}⚠️  Next step: Upload to 1Password/encrypted USB/secure S3${NC}"
else
    echo -e "${YELLOW}⚠ Skipping initial secret backup${NC}"
    echo "  Run later: ./scripts/backup-secrets-only.sh"
fi

# 5. Set up cron jobs (optional)
echo -e "\n${BLUE}[5/5]${NC} Configuring automated backups..."

echo -e "\n${YELLOW}Would you like to set up automated daily backups? (y/n)${NC}"
read -r SETUP_CRON

if [[ "$SETUP_CRON" =~ ^[Yy]$ ]]; then
    # Create cron entries with auto-exclude for secrets
    CRON_ETCD="0 2 * * * ${PROJECT_ROOT}/scripts/backup-etcd.sh >> /var/log/etcd-backup.log 2>&1"
    CRON_FULL="0 1 * * 0 echo \"no\" | ${PROJECT_ROOT}/scripts/full-cluster-backup.sh >> /var/log/cluster-backup.log 2>&1"
    
    # Check if cron entries already exist
    if crontab -l 2>/dev/null | grep -q "backup-etcd.sh"; then
        echo -e "${YELLOW}⚠ Cron jobs already exist${NC}"
    else
        # Add cron jobs
        (crontab -l 2>/dev/null; echo "# Talos cluster backups"; echo "$CRON_ETCD"; echo "$CRON_FULL") | crontab -
        echo -e "${GREEN}✓ Cron jobs added${NC}"
        echo "  - Daily etcd backup: 2:00 AM"
        echo "  - Weekly full backup: 1:00 AM Sunday (secrets EXCLUDED)"
        echo ""
        echo -e "${YELLOW}Note: Automated backups will EXCLUDE secrets (secure default)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Skipping cron setup${NC}"
    echo "  You can manually run backups with:"
    echo "    ${PROJECT_ROOT}/scripts/backup-etcd.sh"
    echo "    ${PROJECT_ROOT}/scripts/full-cluster-backup.sh"
fi

# Display current cron jobs
echo -e "\n${YELLOW}Current backup cron jobs:${NC}"
crontab -l 2>/dev/null | grep -E "backup-(etcd|cluster)" || echo "  None configured"

# Create README in backup directory
cat > "${BACKUP_ROOT}/README.txt" <<EOF
Talos Cluster Backups
=====================

This directory contains automated backups of your Talos Kubernetes cluster.

Directory Structure:
-------------------
etcd/           - Daily etcd snapshots (30 day retention)

⚠️  SECRETS ARE NOT STORED HERE
   Secrets are stored separately in secure vault for security.
   Location: ${SECURE_VAULT}

Backup Scripts:
--------------
${PROJECT_ROOT}/scripts/backup-etcd.sh         - Daily etcd backup
${PROJECT_ROOT}/scripts/full-cluster-backup.sh - Full cluster backup (EXCLUDES secrets)
${PROJECT_ROOT}/scripts/backup-secrets-only.sh - Separate secret backup

Manual Backup:
-------------
cd ${PROJECT_ROOT}
./scripts/full-cluster-backup.sh
# Answer: no (to exclude secrets - recommended)

Secret Backup:
-------------
cd ${PROJECT_ROOT}
./scripts/backup-secrets-only.sh
# Backs up to: ${SECURE_VAULT}
# Then upload to 1Password/encrypted USB/secure S3

Restore:
-------
See ${PROJECT_ROOT}/docs/BACKUP_GUIDE.md for detailed restore procedures
See ${PROJECT_ROOT}/docs/DISASTER_RECOVERY_PHILOSOPHY.md for DR strategy

For full restore, you need:
1. Cluster backup (from this directory)
2. Secrets (from secure vault: ${SECURE_VAULT})

Important Notes:
---------------
⚠️  Secrets are stored SEPARATELY for security
⚠️  Regular backups do NOT contain secrets
⚠️  Always backup secrets to 1Password/encrypted storage
⚠️  Test your backups regularly
⚠️  Keep off-site copies of critical backups

Generated: $(date)
EOF

# Summary
echo -e "\n========================================="
echo -e "${GREEN}Backup System Setup Complete!${NC}"
echo "========================================="
echo ""
echo "Configuration:"
echo "  Backup directory: ${BACKUP_ROOT}"
echo "  Secure vault:     ${SECURE_VAULT}"
echo "  Scripts:          ${PROJECT_ROOT}/scripts/"
echo "  Documentation:    ${PROJECT_ROOT}/docs/"
echo ""
echo "Next Steps:"
echo "  ${GREEN}1. Upload secrets to secure storage${NC}"
if [[ "$BACKUP_SECRETS_NOW" =~ ^[Yy]$ ]]; then
    echo "     Secrets are in: ${SECURE_VAULT}"
    echo "     ${YELLOW}⚠️  Upload to 1Password/encrypted USB/S3${NC}"
else
    echo "     Run: ./scripts/backup-secrets-only.sh"
    echo "     Then upload to 1Password/encrypted USB/S3"
fi
echo ""
echo "  2. Test backup system:"
echo "     cd ${PROJECT_ROOT}"
echo "     ./scripts/full-cluster-backup.sh  # Answer: no (exclude secrets)"
echo ""
echo "  3. Review documentation:"
echo "     ${PROJECT_ROOT}/docs/BACKUP_GUIDE.md"
echo "     ${PROJECT_ROOT}/docs/DISASTER_RECOVERY_PHILOSOPHY.md"
echo ""
echo "  4. Test restore procedure (quarterly)"
echo ""
echo "Quick Reference:"
echo "  Regular backup:  ${PROJECT_ROOT}/scripts/full-cluster-backup.sh"
echo "  Secret backup:   ${PROJECT_ROOT}/scripts/backup-secrets-only.sh"
echo "  List backups:    ls -lh ${BACKUP_ROOT}/"
echo "  List secrets:    ls -lh ${SECURE_VAULT}/"
echo "  View cron jobs:  crontab -l"
echo ""
echo -e "${BLUE}Important Security Notes:${NC}"
echo "  • Regular backups EXCLUDE secrets (by default)"
echo "  • Secrets are stored in: ${SECURE_VAULT}"
echo "  • Upload secrets to 1Password or encrypted storage"
echo "  • Never commit secrets to Git"
echo "  • Test recovery quarterly"
echo ""
echo "========================================="

exit 0_ROOT}/docs/BACKUP_GUIDE.md"
echo ""
echo "Next Steps:"
echo "  1. Review ${PROJECT_ROOT}/docs/BACKUP_GUIDE.md"
echo "  2. Test backup scripts:"
echo "     cd ${PROJECT_ROOT}"
echo "     ./scripts/backup-etcd.sh"
echo "     ./scripts/full-cluster-backup.sh"
echo "  3. Configure cloud storage (optional)"
echo "  4. Test restore procedure"
echo ""
echo "Quick Commands:"
echo "  Manual backup:  ${PROJECT_ROOT}/scripts/full-cluster-backup.sh"
echo "  List backups:   ls -lh ${BACKUP_ROOT}/"
echo "  View cron jobs: crontab -l"
echo ""
echo "========================================="

exit 0