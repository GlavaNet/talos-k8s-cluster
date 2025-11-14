#!/bin/bash
set -euo pipefail

# Talos version
TALOS_VERSION="v1.11.5"

# Node configurations: "IP SCHEMATIC_ID"
declare -A NODES=(
    ["controlplane-01"]="192.168.99.101 e0d8c0535077fde1afae98de332f6e369adc7d6f424ed45ae2873a3146b29de1"
    ["controlplane-02"]="192.168.99.102 a254dbd7e91eed24352dde063497d43216b00b1919fbd0e44a0eccb48291c855"
    ["controlplane-03"]="192.168.99.103 9aef3339220bbce10f1948276aa879638271b2045c02ded13d1277e002e66cdc"
    ["worker-01"]="192.168.99.111 44624ccf4bc02ff356bc173d257c93bb587a1c3301d386b8d933d24e7af30ce3"
)

# Output directory
OUTPUT_DIR="./images"
mkdir -p "${OUTPUT_DIR}"

echo "Downloading Talos ${TALOS_VERSION} images with pre-configured static IPs..."
echo ""

# Download each image
for NODE in "${!NODES[@]}"; do
    read -r IP SCHEMATIC_ID <<< "${NODES[$NODE]}"
    
    OUTPUT_FILE="${OUTPUT_DIR}/${NODE}.raw.xz"
    URL="https://factory.talos.dev/image/${SCHEMATIC_ID}/${TALOS_VERSION}/metal-arm64.raw.xz"
    
    echo "==> ${NODE} (${IP})"
    echo "    Schematic: ${SCHEMATIC_ID}"
    echo "    Downloading from Image Factory..."
    
    if curl -L --progress-bar -o "${OUTPUT_FILE}" "${URL}"; then
        echo "    ✓ Downloaded: ${OUTPUT_FILE}"
        
        # Decompress
        echo "    Decompressing..."
        xz -d -f "${OUTPUT_FILE}"
        DECOMPRESSED="${OUTPUT_FILE%.xz}"
        echo "    ✓ Ready: ${DECOMPRESSED}"
    else
        echo "    ✗ Failed to download ${NODE}"
        exit 1
    fi
    
    echo ""
done

echo "All images downloaded successfully!"
echo ""
echo "Images location: ${OUTPUT_DIR}/"
ls -lh "${OUTPUT_DIR}/"*.raw

echo ""
echo "Next steps:"
echo "1. Flash each image to its corresponding SD card"
echo "2. Insert SD cards and boot the Raspberry Pis"
echo "3. The nodes will boot with pre-configured static IPs"
echo ""
echo "Example flash command (replace diskX with your SD card):"
echo "  sudo dd if=${OUTPUT_DIR}/controlplane-01.raw of=/dev/diskX bs=4M status=progress conv=fsync"
