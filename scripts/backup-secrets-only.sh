#!/bin/bash
# Backup ONLY secrets to secure vault
# Use this to maintain a separate secure backup of cluster secrets

set -e

# Get script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
VAULT_DIR="${HOME}/secure-vault/cluster-secrets"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "Cluster Secrets Backup"
echo "Timestamp: ${TIMESTAMP}"
echo "========================================="

# Create vault directory with restrictive permissions
mkdir -p "${VAULT_DIR}"
chmod 700 "${VAULT_DIR}"

echo -e "\n${BLUE}Backing up secrets to secure vault...${NC}"
echo "Location: ${VAULT_DIR}"
echo ""

# Backup Talos secrets.yaml
if [ -f "${PROJECT_ROOT}/secrets.yaml" ]; then
    cp "${PROJECT_ROOT}/secrets.yaml" \
        "${VAULT_DIR}/secrets-${TIMESTAMP}.yaml"
    ln -sf "secrets-${TIMESTAMP}.yaml" \
        "${VAULT_DIR}/secrets-latest.yaml"
    chmod 600 "${VAULT_DIR}/secrets-"*.yaml
    echo -e "${GREEN}✓ secrets.yaml${NC}"
else
    echo -e "${RED}✗ secrets.yaml not found${NC}"
    echo "  Expected location: ${PROJECT_ROOT}/secrets.yaml"
fi

# Backup talosconfig
if [ -f "${PROJECT_ROOT}/talos/talosconfig" ]; then
    cp "${PROJECT_ROOT}/talos/talosconfig" \
        "${VAULT_DIR}/talosconfig-${TIMESTAMP}"
    ln -sf "talosconfig-${TIMESTAMP}" \
        "${VAULT_DIR}/talosconfig-latest"
    chmod 600 "${VAULT_DIR}/talosconfig-"*
    echo -e "${GREEN}✓ talosconfig${NC}"
else
    echo -e "${YELLOW}⚠ talosconfig not found${NC}"
    echo "  Expected location: ${PROJECT_ROOT}/talos/talosconfig"
fi

# Backup Flux secrets
if kubectl get namespace flux-system &>/dev/null 2>&1; then
    kubectl get secrets -n flux-system -o yaml > \
        "${VAULT_DIR}/flux-secrets-${TIMESTAMP}.yaml" 2>/dev/null
    ln -sf "flux-secrets-${TIMESTAMP}.yaml" \
        "${VAULT_DIR}/flux-secrets-latest.yaml"
    chmod 600 "${VAULT_DIR}/flux-secrets-"*.yaml
    echo -e "${GREEN}✓ Flux secrets${NC}"
else
    echo -e "${YELLOW}⚠ Flux not installed (skipping Flux secrets)${NC}"
fi

# Create bootstrap documentation
cat > "${VAULT_DIR}/BOOTSTRAP_COMMANDS.txt" <<EOF
Cluster Bootstrap Commands
==========================
Last Updated: ${TIMESTAMP}

Talos Bootstrap:
----------------
talosctl --nodes 192.168.99.101 bootstrap

Flux Bootstrap:
---------------
flux bootstrap github \\
  --owner=\${GITHUB_USER} \\
  --repository=\${GITHUB_REPO} \\
  --branch=main \\
  --path=kubernetes/flux \\
  --personal

Git Repository:
---------------
URL: [Your Git repository URL]
Branch: main
Path: kubernetes/flux

Notes:
------
- Store these commands with your secrets
- Update if you change Git repository
- Keep deploy keys/tokens with Flux secrets
EOF

chmod 600 "${VAULT_DIR}/BOOTSTRAP_COMMANDS.txt"
echo -e "${GREEN}✓ Bootstrap commands documented${NC}"

# Show what was backed up
echo -e "\n${BLUE}Backed up files:${NC}"
ls -lh "${VAULT_DIR}"/ | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'

# Calculate vault size
VAULT_SIZE=$(du -sh "${VAULT_DIR}" | cut -f1)

echo ""
echo "========================================="
echo -e "${GREEN}Secrets backed up successfully!${NC}"
echo "========================================="
echo "Location: ${VAULT_DIR}"
echo "Size: ${VAULT_SIZE}"
echo "Permissions: 700 (directory), 600 (files)"
echo ""
echo -e "${YELLOW}NEXT STEPS (CRITICAL):${NC}"
echo "========================================="
echo ""
echo "1. Choose secure storage method:"
echo ""
echo "   ${GREEN}Option A: 1Password (Recommended)${NC}"
echo "   • Create vault 'Cluster Secrets'"
echo "   • Add secure note for each file"
echo "   • Easy sharing, mobile access"
echo ""
echo "   ${GREEN}Option B: Encrypted USB Drive${NC}"
echo "   • Complete air-gap security"
echo "   • Physical control"
echo "   • Store in safe/secure location"
echo ""
echo "   ${GREEN}Option C: Encrypted Cloud (S3)${NC}"
echo "   • Redundant, versioned storage"
echo "   • Accessible from anywhere"
echo "   • Requires proper IAM/encryption"
echo ""
echo "2. Upload/encrypt secrets:"
echo ""
echo "   # Encrypt with GPG:"
echo "   gpg --encrypt --recipient your@email.com \\"
echo "     ${VAULT_DIR}/secrets-latest.yaml"
echo ""
echo "   # Or create encrypted archive:"
echo "   tar czf - ${VAULT_DIR} | \\"
echo "     gpg --encrypt --recipient your@email.com > \\"
echo "     cluster-secrets-${TIMESTAMP}.tar.gz.gpg"
echo ""
echo "3. Verify backup:"
echo "   • Can you access the encrypted files?"
echo "   • Do you have the decryption key?"
echo "   • Test restoration process"
echo ""
echo "4. Clean up (optional):"
echo "   # After uploading to secure storage"
echo "   # rm -rf ${VAULT_DIR}"
echo ""
echo "========================================="
echo ""
echo -e "${RED}⚠️  IMPORTANT SECURITY NOTES:${NC}"
echo "  • Never commit these files to Git"
echo "  • Never upload unencrypted to cloud"
echo "  • Store decryption keys separately"
echo "  • Test recovery process regularly"
echo "  • Update vault when secrets change"
echo ""
echo "========================================="

# Optional: Show helper commands
echo -e "\n${BLUE}Helper Commands:${NC}"
echo ""
echo "View latest secrets:"
echo "  cat ${VAULT_DIR}/secrets-latest.yaml"
echo ""
echo "List all versions:"
echo "  ls -lht ${VAULT_DIR}/"
echo ""
echo "Create encrypted backup:"
echo "  tar czf - ${VAULT_DIR} | gpg -e -r you@email.com > secrets-backup.tar.gz.gpg"
echo ""
echo "Restore from encrypted backup:"
echo "  gpg -d secrets-backup.tar.gz.gpg | tar xzf -"
echo ""

exit 0