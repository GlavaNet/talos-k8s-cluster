# Talos Kubernetes Cluster on Raspberry Pi 4B

Production-ready, highly-available Kubernetes cluster running on Raspberry Pi 4B devices with Talos OS, managed through GitOps using FluxCD.

[![Talos](https://img.shields.io/badge/Talos-v1.11.5-blue)](https://www.talos.dev/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.31+-326CE5)](https://kubernetes.io/)
[![FluxCD](https://img.shields.io/badge/FluxCD-v2.x-5468FF)](https://fluxcd.io/)
[![MetalLB](https://img.shields.io/badge/MetalLB-v0.14.9-orange)](https://metallb.universe.tf/)

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Deployment Guide](#detailed-deployment-guide)
- [Post-Deployment](#post-deployment)
- [Troubleshooting](#troubleshooting)
- [Maintenance & Operations](#maintenance--operations)
- [Repository Structure](#repository-structure)
- [Contributing](#contributing)

---

## Overview

This repository provides Infrastructure as Code (IaC) for deploying a highly-available Kubernetes cluster on Raspberry Pi 4B hardware using:

- **Talos OS**: Immutable, API-driven Linux distribution built for Kubernetes
- **Pre-baked Images**: Custom images with static IPs from Talos Image Factory
- **MetalLB**: Bare-metal load balancer for LoadBalancer service type
- **FluxCD**: GitOps continuous delivery for automatic application deployment
- **High Availability**: 3-node control plane with VIP for API server access

**Key Features:**
- ✅ Fully declarative - entire cluster defined in Git
- ✅ Repeatable deployments - rebuild from scratch in minutes
- ✅ No SSH or shell access - API-only management
- ✅ Automatic updates - GitOps workflow with Flux
- ✅ Production-ready - HA control plane with etcd quorum

---

## Architecture

### Cluster Topology

```
Network: 192.168.99.0/24

                    ┌─────────────────┐
                    │  VIP (HA API)   │
                    │ 192.168.99.100  │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
    ┌────▼────┐         ┌────▼────┐        ┌────▼────┐
    │  CP-01  │         │  CP-02  │        │  CP-03  │
    │  .101   │◄────────┤  .102   │◄───────┤  .103   │
    │ etcd    │   HA    │ etcd    │  HA    │ etcd    │
    └────┬────┘         └────┬────┘        └────┬────┘
         │                   │                   │
         └───────────────────┼───────────────────┘
                             │
                        ┌────▼────┐
                        │ Worker  │
                        │  .111   │
                        └─────────┘
```

### IP Allocation

| Component | IP Range | Purpose |
|-----------|----------|---------|
| Gateway | 192.168.99.1 | Router |
| VIP | 192.168.99.100 | Kubernetes API HA endpoint |
| Control Planes | 192.168.99.101-103 | Control plane nodes (3x) |
| Workers | 192.168.99.111+ | Worker nodes |
| MetalLB Pool | 192.168.99.120-140 | LoadBalancer services (21 IPs) |

### Node Specifications

| Node | Role | IP | Schematic ID (last 8) |
|------|------|----|-----------------------|
| controlplane-01 | Control Plane | 192.168.99.101 | ...b29de1 |
| controlplane-02 | Control Plane | 192.168.99.102 | ...91c855 |
| controlplane-03 | Control Plane | 192.168.99.103 | ...e66cdc |
| worker-01 | Worker | 192.168.99.111 | ...f30ce3 |

**Note:** Control planes are configured with `allowSchedulingOnControlPlanes: true` for efficient resource utilization.

---

## Prerequisites

### Hardware Requirements

- **4x Raspberry Pi 4B** (4GB RAM minimum, 8GB recommended)
- **4x microSD cards** (32GB+ Class 10/A1 or better)
  - Or 4x USB 3.0 drives for better performance
- **Network switch** (all nodes on same Layer 2 network)
- **Stable power supply** (2.5A+ per Pi)

### Software Requirements

Install these tools on your workstation:

```bash
# Talos CLI
curl -sL https://talos.dev/install | sh

# kubectl
# macOS: brew install kubectl
# Linux: https://kubernetes.io/docs/tasks/tools/

# Flux CLI
curl -s https://fluxcd.io/install.sh | sudo bash

# Verify installations
talosctl version
kubectl version --client
flux version
```

### Network Requirements

- **Static IPs reserved**: 192.168.99.100-111, 192.168.99.120-140
- **DHCP exclusions**: Configure router to exclude above IPs
- **Layer 2 connectivity**: All nodes on same VLAN/subnet
- **Firewall rules**: Allow ports 50000 (Talos API), 6443 (K8s API)

### GitHub Setup

```bash
# Generate GitHub Personal Access Token with 'repo' permissions
# https://github.com/settings/tokens

# Export credentials
export GITHUB_TOKEN=<your-token>
export GITHUB_USER=<your-username>
export GITHUB_REPO=<your-repo-name>
```

---

## Quick Start

**For experienced users - full guide below:**

```bash
# 1. Clone repository
git clone https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git
cd ${GITHUB_REPO}

# 2. Download images
chmod +x scripts/download-talos-images.sh
./scripts/download-talos-images.sh

# 3. Flash to SD cards (repeat for all 4 nodes)
sudo dd if=images/controlplane-01.raw of=/dev/sdX bs=4M status=progress conv=fsync

# 4. Boot nodes and generate configs
chmod +x scripts/generate-configs.sh
./scripts/generate-configs.sh

# 5. Apply configurations
chmod +x scripts/apply-configs.sh
./scripts/apply-configs.sh

# 6. Bootstrap cluster
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh

# 7. Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
kubectl apply -f kubernetes/infrastructure/metallb/

# 8. Bootstrap Flux
flux bootstrap github \
  --owner=${GITHUB_USER} \
  --repository=${GITHUB_REPO} \
  --branch=main \
  --path=kubernetes/flux \
  --personal
```

---

## Detailed Deployment Guide

### Step 1: Prepare Images

#### 1.1 Download Node-Specific Images

Each node has a pre-configured image with static IP address baked in:

```bash
cd scripts
chmod +x download-talos-images.sh
./download-talos-images.sh
```

This downloads 4 images to `images/`:
- `controlplane-01.raw` (192.168.99.101)
- `controlplane-02.raw` (192.168.99.102)
- `controlplane-03.raw` (192.168.99.103)
- `worker-01.raw` (192.168.99.111)

**Verify downloads:**
```bash
ls -lh images/
# Should show 4 .raw files, ~300MB each
```

#### 1.2 Flash SD Cards

**Label your SD cards** before flashing to avoid confusion!

**macOS:**
```bash
# Find SD card
diskutil list

# Unmount (replace diskX)
diskutil unmountDisk /dev/diskX

# Flash image
sudo dd if=images/controlplane-01.raw of=/dev/rdiskX bs=4m status=progress

# Eject
diskutil eject /dev/diskX
```

**Linux:**
```bash
# Find SD card
lsblk

# Flash image (replace sdX)
sudo dd if=images/controlplane-01.raw of=/dev/sdX bs=4M status=progress conv=fsync

# Sync
sync
```

**Windows:**
- Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
- Select "Use custom" and choose `.raw` file
- Write to SD card

**Repeat for all 4 nodes**, ensuring correct image matches each node.

---

### Step 2: Boot Nodes

1. Insert SD cards into Raspberry Pis
2. Connect all nodes to network switch
3. Connect switch to router
4. Power on all nodes
5. Wait 2-3 minutes for boot

#### 2.1 Verify Node Discovery

```bash
# Scan for Talos nodes
nmap -p 50000 192.168.99.0/24 | grep -B 4 "50000/tcp open"

# Or test specific IPs
for ip in 192.168.99.{101..103} 192.168.99.111; do
  echo -n "$ip: "
  nc -zv $ip 50000 2>&1 | grep succeeded && echo "✓ Ready"
done
```

**Expected output:**
```
192.168.99.101: ✓ Ready
192.168.99.102: ✓ Ready
192.168.99.103: ✓ Ready
192.168.99.111: ✓ Ready
```

**If nodes don't appear:**
- Check power connections
- Verify network connectivity
- Ensure SD cards were flashed correctly
- Check router DHCP logs (nodes shouldn't need DHCP)
- Wait longer (first boot can take 3-5 minutes)

---

### Step 3: Generate Talos Configurations

#### 3.1 Run Generation Script

```bash
cd scripts
chmod +x generate-configs.sh
./generate-configs.sh
```

This creates:
- `talos/secrets.yaml` - Cluster secrets (⚠️ **KEEP SAFE**)
- `talos/talosconfig` - Talos API credentials
- `talos/controlplane/*.yaml` - Node configurations
- `talos/worker/*.yaml` - Worker configurations

#### 3.2 Backup Secrets

**CRITICAL:** Store secrets securely before proceeding:

```bash
# Option 1: Offline backup
cp talos/secrets.yaml ~/secure-backup/talos-secrets-$(date +%Y%m%d).yaml

# Option 2: Encrypted backup (recommended for Git)
# Install SOPS: https://github.com/mozilla/sops
sops --encrypt talos/secrets.yaml > talos/secrets.enc.yaml
git add talos/secrets.enc.yaml

# Option 3: Password manager
# Store secrets.yaml in 1Password/Bitwarden/etc
```

**Without `secrets.yaml`, you cannot:**
- Add new nodes to cluster
- Recover from complete cluster failure
- Generate new configurations

---

### Step 4: Apply Configurations

#### 4.1 Apply to All Nodes

**CRITICAL SEQUENCE:** Apply configs to ALL nodes BEFORE bootstrapping.

```bash
cd scripts
chmod +x apply-configs.sh
./apply-configs.sh
```

The script applies configurations in order:
1. controlplane-01 → wait 30s
2. controlplane-02 → wait 30s
3. controlplane-03 → wait 30s
4. worker-01 → done

**Manual application (if script fails):**
```bash
export TALOSCONFIG="./talos/talosconfig"

talosctl apply-config \
  --nodes 192.168.99.101 \
  --file talos/controlplane/controlplane-01.yaml \
  --insecure

# Wait for node to process config
sleep 30

# Repeat for other nodes...
```

#### 4.2 Verify Configuration Applied

```bash
# Check node status
talosctl --nodes 192.168.99.101 version --insecure

# Should show Talos version, NOT "maintenance mode"
```

**If nodes stay in maintenance mode:**
- Configs weren't applied correctly
- Re-run apply-configs.sh
- Check network connectivity
- See [Troubleshooting](#troubleshooting) section

---

### Step 5: Bootstrap Cluster

#### 5.1 Bootstrap First Control Plane

```bash
cd scripts
chmod +x bootstrap.sh
./bootstrap.sh
```

**What happens:**
1. Initializes etcd on controlplane-01
2. Starts Kubernetes control plane components
3. Other control planes join automatically
4. Worker node joins automatically
5. VIP becomes active (192.168.99.100)
6. Retrieves kubeconfig

**This takes 5-10 minutes on Raspberry Pi.**

#### 5.2 Monitor Bootstrap Progress

```bash
# Watch bootstrap logs
talosctl --nodes 192.168.99.101 dmesg --follow

# Check cluster health
talosctl --nodes 192.168.99.101 health

# Check etcd members
talosctl --nodes 192.168.99.101 etcdctl member list
```

#### 5.3 Verify Cluster

```bash
# Set kubeconfig
export KUBECONFIG=./kubeconfig

# Check nodes
kubectl get nodes -o wide

# Expected output:
# NAME              STATUS   ROLES           AGE   VERSION
# controlplane-01   Ready    control-plane   5m    v1.31.x
# controlplane-02   Ready    control-plane   4m    v1.31.x
# controlplane-03   Ready    control-plane   4m    v1.31.x
# worker-01         Ready    <none>          3m    v1.31.x

# Check system pods
kubectl get pods -A

# All kube-system pods should be Running
```

**If bootstrap fails:**
- Check [Troubleshooting: Bootstrap Failures](#bootstrap-failures)
- Review logs: `talosctl --nodes 192.168.99.101 logs kubelet`

---

### Step 6: Install MetalLB

MetalLB provides LoadBalancer service type for bare metal clusters.

#### 6.1 Install MetalLB Components

```bash
# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

# Wait for pods
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s
```

#### 6.2 Configure IP Address Pool

```bash
# Apply MetalLB configuration
kubectl apply -f kubernetes/infrastructure/metallb/

# Verify
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

#### 6.3 Test MetalLB

```bash
# Create test service
kubectl create deployment nginx --image=nginx --replicas=2
kubectl expose deployment nginx --type=LoadBalancer --port=80

# Check assigned IP
kubectl get svc nginx

# Should show EXTERNAL-IP from MetalLB pool (192.168.99.120-140)

# Test access
NGINX_IP=$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://${NGINX_IP}

# Clean up
kubectl delete svc nginx
kubectl delete deployment nginx
```

---

### Step 7: Bootstrap FluxCD

FluxCD enables GitOps - automatic synchronization between Git and cluster state.

#### 7.1 Pre-flight Check

```bash
flux check --pre

# Should show: ✔ all checks passed
```

#### 7.2 Bootstrap Flux

```bash
flux bootstrap github \
  --owner=${GITHUB_USER} \
  --repository=${GITHUB_REPO} \
  --branch=main \
  --path=kubernetes/flux \
  --personal \
  --token-string=${GITHUB_TOKEN}
```

**What this does:**
1. Installs Flux components in `flux-system` namespace
2. Creates/updates GitHub repository
3. Commits Flux manifests to `kubernetes/flux/flux-system/`
4. Configures Flux to watch repository
5. Begins synchronizing cluster state

#### 7.3 Verify Flux Installation

```bash
# Check Flux components
flux get sources git
flux get kustomizations

# Check pods
kubectl get pods -n flux-system

# All flux-system pods should be Running
```

#### 7.4 Configure Flux Structure

Flux watches `kubernetes/` directory for changes. Commit infrastructure and apps:

```bash
# Add infrastructure kustomization
git add kubernetes/flux/flux-system/infrastructure.yaml
git add kubernetes/infrastructure/

# Commit and push
git commit -m "Add infrastructure configuration"
git push origin main

# Watch Flux deploy
flux get kustomizations --watch

# Should show 'infrastructure' reconciling
```

---

## Post-Deployment

### Verify Cluster Health

```bash
# Nodes
kubectl get nodes

# System components
kubectl get pods -A

# Talos services
talosctl --nodes 192.168.99.100 services

# etcd health
talosctl --nodes 192.168.99.100 etcdctl member list
talosctl --nodes 192.168.99.100 etcdctl endpoint health

# VIP status
ping -c 3 192.168.99.100
```

### Update kubeconfig Context

```bash
# Rename context for convenience
kubectl config rename-context admin@talos-cluster prod-rpi-cluster

# Set as default
kubectl config use-context prod-rpi-cluster
```

### Configure Monitoring (Recommended)

```bash
# Add Prometheus Operator
# See kubernetes/apps/monitoring/ for examples

# Access Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80
# Open http://localhost:3000
```

### Set Up Ingress Controller (Optional)

```bash
# Deploy NGINX Ingress
kubectl apply -f kubernetes/infrastructure/ingress-nginx/

# Verify LoadBalancer IP assigned
kubectl get svc -n ingress-nginx
```

---

## Troubleshooting

### Node Discovery Issues

**Problem:** Nodes don't appear on network after boot

**Diagnosis:**
```bash
# Check if Talos API is responding
nc -zv 192.168.99.101 50000

# Scan entire subnet
nmap -p 50000 192.168.99.0/24
```

**Solutions:**
1. **Power issues**: Verify stable 2.5A+ power supply
2. **SD card problems**: Re-flash with new SD card
3. **Network issues**: Test cable, switch port
4. **Wrong network**: Verify router configuration
5. **First boot delay**: Wait 5 minutes, try again

---

### Configuration Not Applying

**Problem:** `apply-config` succeeds but nodes stay in maintenance mode

**Diagnosis:**
```bash
# Check node status
talosctl --nodes 192.168.99.101 version --insecure

# Check disk
talosctl --nodes 192.168.99.101 disks --insecure

# Check logs
talosctl --nodes 192.168.99.101 logs installer --insecure
```

**Solutions:**
1. **Wrong disk path**: Update install disk in config
   ```bash
   # Check available disks
   talosctl --nodes 192.168.99.101 disks --insecure
   # Update machine.install.disk in config
   ```

2. **Config validation error**: Check config syntax
   ```bash
   talosctl validate --config talos/controlplane/controlplane-01.yaml --mode metal
   ```

3. **Network mismatch**: Verify gateway, IP addresses
4. **Apply before bootstrap**: Never bootstrap before applying configs

---

### Bootstrap Failures

**Problem:** Bootstrap command fails or times out

**Diagnosis:**
```bash
# Check control plane logs
talosctl --nodes 192.168.99.101 logs kubelet

# Check etcd
talosctl --nodes 192.168.99.101 service etcd status

# Check API server
talosctl --nodes 192.168.99.101 service kube-apiserver status
```

**Solutions:**

1. **etcd not starting**:
   ```bash
   # Check etcd logs
   talosctl --nodes 192.168.99.101 logs etcd
   
   # Common issue: clock skew
   talosctl --nodes 192.168.99.101 time
   ```

2. **Insufficient resources**: Verify 4GB+ RAM per Pi

3. **Network issues**: Ensure Layer 2 connectivity
   ```bash
   # Test from one node to another
   talosctl --nodes 192.168.99.101 get addresses
   ```

4. **Corrupted state**: Reset and retry
   ```bash
   # Reset node (WARNING: deletes all data)
   talosctl reset --nodes 192.168.99.101 --graceful=false --reboot
   
   # Re-apply config and bootstrap
   ```

---

### VIP Not Responding

**Problem:** Can't reach 192.168.99.100 after bootstrap

**Diagnosis:**
```bash
# Check etcd health (VIP requires healthy etcd)
talosctl --nodes 192.168.99.101 service etcd status

# Check VIP on interfaces
talosctl --nodes 192.168.99.101,192.168.99.102,192.168.99.103 get addresses | grep 192.168.99.100

# Check etcd members
talosctl --nodes 192.168.99.101 etcdctl member list
```

**Solutions:**

1. **etcd not healthy**: Wait for etcd to stabilize
   ```bash
   # Monitor etcd
   talosctl --nodes 192.168.99.101 etcdctl endpoint health --cluster
   ```

2. **VIP not configured**: Verify VIP in machine configs
   ```yaml
   machine:
     network:
       interfaces:
         - deviceSelector:
             physical: true
           vip:
             ip: 192.168.99.100
   ```

3. **Wrong subnet**: VIP must be in same subnet as nodes

4. **ARP issues**: Check switch configuration, disable port security

---

### MetalLB Not Assigning IPs

**Problem:** LoadBalancer services stuck with `<pending>` EXTERNAL-IP

**Diagnosis:**
```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# Check logs
kubectl logs -n metallb-system -l app=metallb -l component=controller
kubectl logs -n metallb-system -l app=metallb -l component=speaker

# Check configuration
kubectl get ipaddresspool -n metallb-system -o yaml
kubectl get l2advertisement -n metallb-system -o yaml

# Check service events
kubectl describe svc <service-name>
```

**Solutions:**

1. **IP pool conflicts with DHCP**:
   - Reserve IPs in router
   - Update IP pool range

2. **Interface mismatch**:
   ```yaml
   # Update l2-advertisement.yaml
   spec:
     interfaces:
       - eth0  # Verify this matches your Pi's interface
   ```

3. **MetalLB pods not running**:
   ```bash
   # Reinstall MetalLB
   kubectl delete namespace metallb-system
   kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
   ```

4. **Strict ARP mode required**:
   ```bash
   # Check kube-proxy config (Talos enables by default)
   talosctl --nodes 192.168.99.100 get kubeproxyconfigs -o yaml
   ```

---

### Flux Not Reconciling

**Problem:** Changes in Git not reflected in cluster

**Diagnosis:**
```bash
# Check Flux health
flux check

# Check reconciliation
flux get sources git
flux get kustomizations

# Check logs
kubectl logs -n flux-system -l app=source-controller
kubectl logs -n flux-system -l app=kustomize-controller

# Check events
flux events
```

**Solutions:**

1. **Git authentication failed**:
   ```bash
   # Verify GitHub token
   kubectl get secret -n flux-system flux-system -o yaml
   
   # Re-bootstrap with new token
   flux bootstrap github --force ...
   ```

2. **Invalid manifests**:
   ```bash
   # Force reconcile to see errors
   flux reconcile source git flux-system
   flux reconcile kustomization flux-system
   ```

3. **Dependency issues**: Check kustomization dependencies
   ```yaml
   # Ensure proper order
   dependsOn:
     - name: infrastructure
   ```

4. **Suspended reconciliation**:
   ```bash
   # Check if suspended
   flux get kustomizations
   
   # Resume
   flux resume kustomization <name>
   ```

---

### Node Not Joining Cluster

**Problem:** Node appears in Talos but not in `kubectl get nodes`

**Diagnosis:**
```bash
# Check kubelet status
talosctl --nodes <IP> service kubelet status

# Check kubelet logs
talosctl --nodes <IP> logs kubelet

# Check node conditions
kubectl describe node <node-name>
```

**Solutions:**

1. **Certificate issues**: Check time synchronization
   ```bash
   talosctl --nodes <IP> time
   ```

2. **Network policy blocking**: Check CNI
   ```bash
   kubectl get pods -n kube-system | grep flannel
   ```

3. **Kubelet not running**:
   ```bash
   talosctl --nodes <IP> service kubelet restart
   ```

---

### Disk Space Issues

**Problem:** SD card fills up

**Diagnosis:**
```bash
# Check disk usage
talosctl --nodes 192.168.99.101 df

# Check large directories
talosctl --nodes 192.168.99.101 du /system
```

**Solutions:**

1. **Clean container images**:
   ```bash
   # Talos auto-cleans, but can force
   talosctl --nodes 192.168.99.101 service containerd restart
   ```

2. **Rotate logs**: Talos automatically rotates
3. **Use larger SD card**: Reflash with 64GB+ card

---

### Complete Cluster Reset

**When all else fails:**

```bash
# 1. Reset all nodes (WARNING: DESTROYS ALL DATA)
for ip in 192.168.99.{101..103} 192.168.99.111; do
  talosctl reset --nodes $ip --graceful=false --reboot
done

# 2. Wait for maintenance mode (3-5 minutes)

# 3. Re-apply configurations
./scripts/apply-configs.sh

# 4. Bootstrap
./scripts/bootstrap.sh

# 5. Reinstall MetalLB and Flux
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
kubectl apply -f kubernetes/infrastructure/metallb/
flux bootstrap github ...
```

---

## Maintenance & Operations

### Upgrading Talos

```bash
# Check current version
talosctl --nodes 192.168.99.100 version

# Upgrade nodes one at a time
# Get new schematic from factory.talos.dev with new version
talosctl --nodes 192.168.99.101 upgrade \
  --image factory.talos.dev/installer/<schematic-id>:v1.11.6 \
  --preserve

# Wait for node to reboot and rejoin
kubectl wait --for=condition=Ready node/controlplane-01 --timeout=10m

# Repeat for other nodes
```

### Upgrading Kubernetes

```bash
# Check available versions
talosctl --nodes 192.168.99.100 upgrade-k8s --dry-run

# Upgrade (updates all control planes and workers)
talosctl --nodes 192.168.99.100 upgrade-k8s --to 1.32.0
```

### Adding New Nodes

```bash
# 1. Generate schematic with static IP at factory.talos.dev
# 2. Download and flash image
# 3. Boot node
# 4. Update generate-configs.sh with new node
# 5. Generate and apply config
talosctl apply-config --nodes <new-ip> --file talos/worker/worker-02.yaml --insecure

# Node automatically joins cluster
```

### Backup etcd

```bash
# Take snapshot
talosctl --nodes 192.168.99.101 etcd snapshot /var/lib/etcd/snapshot.db

# Copy locally
talosctl --nodes 192.168.99.101 copy /var/lib/etcd/snapshot.db ./etcd-backup-$(date +%Y%m%d).db
```

### Restore etcd

```bash
# Restore snapshot (only if disaster recovery needed)
talosctl --nodes 192.168.99.101 etcd snapshot /path/to/snapshot.db --restore
```

### Update Node Configuration

```bash
# Edit patch file
vim talos/controlplane/controlplane-01-patch.yaml

# Regenerate config
./scripts/generate-configs.sh

# Apply (no --insecure after initial setup)
talosctl apply-config --nodes 192.168.99.101 --file talos/controlplane/controlplane-01.yaml
```

---

## Repository Structure

```
├── scripts/                     # Automation scripts
│   ├── download-talos-images.sh # Download node images
│   ├── generate-configs.sh      # Generate Talos configs
│   ├── apply-configs.sh         # Apply configs to nodes
│   └── bootstrap.sh             # Bootstrap cluster
│
├── talos/                       # Talos configuration
│   ├── secrets.yaml             # Cluster secrets (gitignored)
│   ├── talosconfig              # Talos API config (gitignored)
│   ├── controlplane/            # Control plane configs
│   └── worker/                  # Worker configs
│
├── kubernetes/                  # Kubernetes manifests
│   ├── flux/                    # Flux system configs
│   ├── infrastructure/          # Core services (MetalLB, etc)
│   └── apps/                    # Application deployments
│
└── docs/                        # Documentation
```

**See [Repository Structure](docs/repository-structure.md) for details.**

---

## Contributing

### Reporting Issues

Found a bug or have a suggestion? Please:
1. Check existing [GitHub Issues](../../issues)
2. Create new issue with:
   - Clear description
   - Steps to reproduce
   - Expected vs actual behavior
   - Logs/screenshots if applicable

### Submitting Changes

1. Fork the repository
2. Create feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -m 'Add my feature'`
4. Push branch: `git push origin feature/my-feature`
5. Open Pull Request

### Testing Changes

Before submitting:
```bash
# Validate Talos configs
talosctl validate --config talos/controlplane/controlplane-01.yaml --mode metal

# Validate Kubernetes manifests
kubectl apply --dry-run=client -f kubernetes/infrastructure/

# Test Flux reconciliation
flux reconcile source git flux-system --with-source
```

---

## Support

- **Documentation**: [Talos Docs](https://www.talos.dev/) | [Flux Docs](https://fluxcd.io/)
- **Community**: 
  - [Talos Discussions](https://github.com/siderolabs/talos/discussions)
  - [Flux Slack](https://cloud-native.slack.com/)
  - [k8s@home Discord](https://discord.gg/k8s-at-home)

---

## License

This repository is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) - Inspiration for GitOps structure
- [Talos Team](https://github.com/siderolabs/talos) - Excellent immutable OS
- [k8s@home community](https://github.com/k8s-at-home) - Helpful community support

---

**Built with ❤️ for homelab enthusiasts and production Pi clusters**
