#!/bin/bash
set -e

IMAGES_DIR="talos-images"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Download Verified Factory Images"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

mkdir -p "$IMAGES_DIR"

# Array of node names, IPs, and schematic IDs
declare -A NODES=(
    ["controlplane-01"]="192.168.99.101 e0d8c0535077fde1afae98de332f6e369adc7d6f424ed45ae2873a3146b29de1"
    ["controlplane-02"]="192.168.99.102 a254dbd7e91eed24352dde063497d43216b00b1919fbd0e44a0eccb48291c855"
    ["controlplane-03"]="192.168.99.103 9aef3339220bbce10f1948276aa879638271b2045c02ded13d1277e002e66cdc"
    ["worker-01"]="192.168.99.111 44624ccf4bc02ff356bc173d257c93bb587a1c3301d386b8d933d24e7af30ce3"
)

TALOS_VERSION="v1.11.5"
SUCCESS=0
FAILED=0

for NODE in "${!NODES[@]}"; do
    read IP SCHEMATIC_ID <<< "${NODES[$NODE]}"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "${NODE} (${IP})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Schematic: ${SCHEMATIC_ID}"
    
    IMAGE_URL="https://factory.talos.dev/image/${SCHEMATIC_ID}/${TALOS_VERSION}/metal-arm64.raw.xz"
    OUTPUT_FILE="${IMAGES_DIR}/${NODE}.raw.xz"
    
    echo "URL: $IMAGE_URL"
    echo ""
    
    if curl -L -f --progress-bar "$IMAGE_URL" -o "$OUTPUT_FILE"; then
        SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
        echo ""
        echo "✓ Downloaded: $SIZE"
        SUCCESS=$((SUCCESS + 1))
    else
        echo ""
        echo "✗ Download failed"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Download Summary: $SUCCESS successful, $FAILED failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $SUCCESS -eq 4 ]; then
    echo ""
    echo "✓ All images downloaded!"
    echo ""
    ls -lh "${IMAGES_DIR}/"*.xz
    echo ""
    echo "Next: ./scripts/flash-all-images-xz.sh"
else
    echo ""
    echo "⚠ Some downloads failed"
fi
