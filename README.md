# Talos Kubernetes Cluster on Raspberry Pi 4B

Production-ready, highly-available Kubernetes cluster running on Raspberry Pi 4B devices with Talos OS, managed through GitOps using FluxCD.

[![Talos](https://img.shields.io/badge/Talos-v1.11.5-blue)](https://www.talos.dev/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.31+-326CE5)](https://kubernetes.io/)
[![FluxCD](https://img.shields.io/badge/FluxCD-v2.x-5468FF)](https://fluxcd.io/)
[![MetalLB](https://img.shields.io/badge/MetalLB-v0.14.9-orange)](https://metallb.universe.tf/)
[![Traefik](https://img.shields.io/badge/Traefik-v3.1-24A1C1)](https://traefik.io/)

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Deployed Components](#deployed-components)
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
- **Traefik**: Modern HTTP reverse proxy and load balancer
- **FluxCD**: GitOps continuous delivery for automatic application deployment
- **High Availability**: 3-node control plane with VIP for API server access

**Key Features:**
- ✅ Fully declarative - entire cluster defined in Git
- ✅ Repeatable deployments - rebuild from scratch in minutes
- ✅ No SSH or shell access - API-only management
- ✅ Automatic updates - GitOps workflow with Flux
- ✅ Production-ready - HA control plane with etcd quorum
- ✅ Ingress ready - Traefik deployed for HTTP/HTTPS routing

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
                        │  Pods   │
                        └─────────┘

MetalLB IP Pool: 192.168.99.120-140 (21 IPs)
```

### Hardware Specifications

| Component | Specification |
|-----------|---------------|
| **Nodes** | 4x Raspberry Pi 4B (8GB RAM) |
| **Storage** | High-endurance microSD cards (32GB+) |
| **Network** | Gigabit Ethernet (wired) |
| **Power** | USB-C 3A power supplies |
| **OS** | Talos Linux (immutable) |

---

## Deployed Components

### Core Infrastructure

| Component | Version | Purpose | Status |
|-----------|---------|---------|--------|
| **Talos OS** | v1.11.5 | Immutable OS for Kubernetes | ✅ Active |
| **Kubernetes** | v1.31+ | Container orchestration | ✅ Active |
| **FluxCD** | v2.x | GitOps continuous delivery | ✅ Active |
| **MetalLB** | v0.14.9 | Load balancer (Layer 2) | ✅ Active |
| **Traefik** | v3.1 | Ingress controller & reverse proxy | ✅ Active |

### Applications

| Application | Purpose | Namespace | Credentials |
|-------------|---------|-----------|-------------|
| **AdGuardHome** | Network-wide DNS ad blocker | `adguardhome` | Set during bootstrap |
| **Vaultwarden** | Self-hosted password manager | `vaultwarden` | Admin token set during bootstrap |

All applications are automatically deployed and managed by FluxCD after cluster bootstrap.

### Network Configuration

- **Pod Network**: `10.244.0.0/16` (Flannel CNI)
- **Service Network**: `10.96.0.0/12`
- **MetalLB Pool**: `192.168.99.120-140`
- **Traefik LoadBalancer**: `192.168.99.120`
- **Cluster VIP**: `192.168.99.100`

### Traefik Configuration

Traefik is deployed as a DaemonSet with the following features:
- HTTP (port 80) and HTTPS (port 443) entry points
- HTTP/3 support enabled
- LoadBalancer service type using MetalLB
- Dashboard available at `traefik.glavanet.local`
- Prometheus metrics endpoint
- Access logging enabled
- Local traffic policy for source IP preservation

---

## Prerequisites

### Required Tools

Install these on your local machine:

```bash
# macOS
brew install talosctl kubectl flux

# Linux
curl -sL https://talos.dev/install | sh
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -s https://fluxcd.io/install.sh | bash

# Verify installations
talosctl version
kubectl version --client
flux version
```

### Required Accounts & Credentials

1. **GitHub Account**: For GitOps repository
2. **GitHub Personal Access Token**: 
   - Scopes: `repo`, `workflow`
   - Create at: https://github.com/settings/tokens

### Network Requirements

- **Static IP Range**: Available IPs in `192.168.99.0/24`
- **Reserved IPs**:
  - `192.168.99.100`: Cluster VIP (HA API)
  - `192.168.99.101-103`: Control plane nodes
  - `192.168.99.111`: Worker node
  - `192.168.99.120-140`: MetalLB pool

---

## Quick Start

For experienced users who want to get running quickly:

```bash
# 1. Clone repository
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO

# 2. Set environment variables
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxx
export GITHUB_USER=your-username
export GITHUB_REPO=your-repo-name

# 3. Download and flash Talos images
./scripts/download-talos-images.sh

# 4. Flash images to SD cards and boot Pis

# 5. Generate cluster configurations
./scripts/generate-configs.sh

# 6. Apply configurations
./scripts/apply-configs.sh

# 7. Bootstrap cluster (will prompt for AdGuardHome & Vaultwarden credentials)
./scripts/bootstrap.sh

# 8. Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s
kubectl apply -f kubernetes/infrastructure/metallb/

# 9. Bootstrap FluxCD
flux bootstrap github \
  --owner=${GITHUB_USER} \
  --repository=${GITHUB_REPO} \
  --branch=main \
  --path=kubernetes/flux \
  --personal \
  --token-string=${GITHUB_TOKEN}

# 10. Verify deployment
kubectl get nodes
kubectl get pods -A
flux get kustomizations
```

---

## Detailed Deployment Guide

### Step 1: Prepare Talos Images

#### 1.1 Access Talos Image Factory

Visit [factory.talos.dev](https://factory.talos.dev) to generate custom images with static IPs.

#### 1.2 Create Schematics

For each node, create a schematic with:
- **Platform**: `metal-rpi_generic`
- **Extensions**: None required for basic setup
- **Customizations**: Static network configuration

Example for `controlplane-01`:
```yaml
networking:
  interfaces:
    - interface: eth0
      addresses:
        - 192.168.99.101/24
      routes:
        - network: 0.0.0.0/0
          gateway: 192.168.99.1
      dhcp: false
  hostname: controlplane-01
  nameservers:
    - 192.168.99.1
```

#### 1.3 Download Images

```bash
# Use the download script
./scripts/download-talos-images.sh

# Or manually download from factory.talos.dev
# Images will be in images/ directory
```

#### 1.4 Flash SD Cards

```bash
# macOS
diskutil list  # Find your SD card (e.g., /dev/disk4)
diskutil unmountDisk /dev/diskX
sudo dd if=images/controlplane-01.raw of=/dev/rdiskX bs=4M status=progress
diskutil eject /dev/diskX

# Linux
lsblk  # Find your SD card (e.g., /dev/sdb)
sudo umount /dev/sdX*
sudo dd if=images/controlplane-01.raw of=/dev/sdX bs=4M status=progress conv=fsync
sudo eject /dev/sdX
```

**Flash all 4 nodes with their respective images.**

---

### Step 2: Boot Raspberry Pis

1. Insert SD cards into respective Pis
2. Connect Ethernet cables
3. Connect power supplies
4. Wait 2-3 minutes for boot

#### 2.1 Verify Connectivity

```bash
# Test each node
ping -c 3 192.168.99.101
ping -c 3 192.168.99.102
ping -c 3 192.168.99.103
ping -c 3 192.168.99.111

# Check Talos API
talosctl --nodes 192.168.99.101 version --insecure
```

---

### Step 3: Generate Cluster Configuration

```bash
# Generate secrets and configs
./scripts/generate-configs.sh

# This creates:
# - talos/secrets.yaml (cluster secrets)
# - talos/talosconfig (API credentials)
# - talos/controlplane/*.yaml (node configs)
# - talos/worker/*.yaml (node configs)
```

**Important**: `secrets.yaml` and `talosconfig` are gitignored. Back them up securely!

---

### Step 4: Apply Configurations

```bash
# Apply to all nodes
./scripts/apply-configs.sh

# Or manually:
talosctl apply-config --nodes 192.168.99.101 --file talos/controlplane/controlplane-01.yaml --insecure
talosctl apply-config --nodes 192.168.99.102 --file talos/controlplane/controlplane-02.yaml --insecure
talosctl apply-config --nodes 192.168.99.103 --file talos/controlplane/controlplane-03.yaml --insecure
talosctl apply-config --nodes 192.168.99.111 --file talos/worker/worker-01.yaml --insecure
```

**Nodes will reboot after applying configs.**

---

### Step 5: Bootstrap Cluster

#### 5.1 Bootstrap First Control Plane

```bash
# Run bootstrap script
./scripts/bootstrap.sh
```

**What happens:**
1. Initializes etcd on controlplane-01
2. Starts Kubernetes control plane components
3. Other control planes join automatically
4. Worker node joins automatically
5. VIP becomes active (192.168.99.100)
6. Retrieves kubeconfig
7. **Prompts for application credentials** (see below)

**This takes 5-10 minutes on Raspberry Pi.**

#### 5.2 Application Credential Setup

During bootstrap, the script will prompt you to set up credentials for applications that will be deployed via FluxCD:

**AdGuardHome (DNS Server):**
- Username (default: admin)
- Password (with confirmation)
- Used to access AdGuardHome web interface

**Vaultwarden (Password Manager):**
- Admin token (can be auto-generated)
- Used to access Vaultwarden admin panel

These credentials are stored as Kubernetes secrets and referenced by the application deployments managed by Flux.

#### 5.3 Monitor Bootstrap Progress

```bash
# Watch bootstrap logs
talosctl --nodes 192.168.99.101 dmesg --follow

# Check cluster health
talosctl --nodes 192.168.99.101 health

# Check etcd members
talosctl --nodes 192.168.99.101 etcdctl member list
```

#### 5.4 Verify Cluster

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

MetalLB is configured with:
- **IP Pool**: `192.168.99.120-192.168.99.140` (21 addresses)
- **Mode**: Layer 2
- **Auto-assign**: Enabled

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

#### 7.4 Verify Traefik Deployment

Flux will automatically deploy Traefik from the repository:

```bash
# Check Traefik namespace
kubectl get ns traefik

# Check Traefik pods
kubectl get pods -n traefik

# Check Traefik service (should have LoadBalancer IP)
kubectl get svc -n traefik

# Expected output shows EXTERNAL-IP: 192.168.99.120
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

### Access Traefik Dashboard

```bash
# Port-forward to access dashboard
kubectl port-forward -n traefik $(kubectl get pods -n traefik -l app.kubernetes.io/name=traefik -o name | head -1) 9000:9000

# Open browser to http://localhost:9000/dashboard/
```

### Update kubeconfig Context

```bash
# Rename context for convenience
kubectl config rename-context admin@talos-cluster prod-rpi-cluster

# Set as default
kubectl config use-context prod-rpi-cluster
```

---

## Troubleshooting

### Common Issues

#### Node Discovery Issues

**Problem**: Nodes don't appear on network after boot

**Solutions**:
1. Verify power supply (3A+ recommended)
2. Re-flash SD card with new image
3. Check Ethernet cable and switch port
4. Scan network: `nmap -p 50000 192.168.99.0/24`

#### Bootstrap Failures

**Problem**: Bootstrap hangs or fails

**Solutions**:
1. Check etcd health: `talosctl --nodes 192.168.99.101 etcdctl endpoint health --cluster`
2. Verify VIP configuration in machine configs
3. Review logs: `talosctl --nodes 192.168.99.101 logs kubelet`
4. Increase timeout and retry

#### MetalLB Not Assigning IPs

**Problem**: LoadBalancer services stuck with `<pending>` EXTERNAL-IP

**Solutions**:
1. Check MetalLB pods: `kubectl get pods -n metallb-system`
2. Verify IP pool doesn't conflict with DHCP
3. Check logs: `kubectl logs -n metallb-system -l component=controller`
4. Verify interface in L2Advertisement matches node interface (eth0)

#### Flux Not Reconciling

**Problem**: Changes in Git not reflected in cluster

**Solutions**:
1. Check Flux health: `flux check`
2. Force reconcile: `flux reconcile source git flux-system`
3. Check events: `flux events`
4. Verify GitHub token is valid

#### Traefik Issues

**Problem**: Ingress not routing traffic

**Solutions**:
1. Check Traefik pods: `kubectl get pods -n traefik`
2. View logs: `kubectl logs -n traefik -l app.kubernetes.io/name=traefik`
3. Verify DNS/hosts file points to MetalLB IP (192.168.99.120)
4. Check Ingress resource: `kubectl get ingress -A`

### Disk Space Issues

**Problem**: SD card running out of space

**Solutions**:
```bash
# Check disk usage
talosctl --nodes 192.168.99.100 df

# Cleanup options:
# 1. Talos automatically rotates logs
# 2. Clean up old container images (Talos handles this)
# 3. Use larger SD card (64GB+ recommended)
```

### Complete Cluster Reset

**When all else fails:**

```bash
# WARNING: DESTROYS ALL DATA
for ip in 192.168.99.{101..103} 192.168.99.111; do
  talosctl reset --nodes $ip --graceful=false --reboot
done

# Wait for maintenance mode (3-5 minutes)
# Then re-run deployment from Step 4
```

---

## Maintenance & Operations

### Upgrading Talos

```bash
# Check current version
talosctl --nodes 192.168.99.100 version

# Upgrade nodes one at a time
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

### Adding New Worker Nodes

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

### Update Node Configuration

```bash
# Edit patch file
vim talos/controlplane/controlplane-01-patch.yaml

# Regenerate config
./scripts/generate-configs.sh

# Apply (no --insecure after initial setup)
talosctl apply-config --nodes 192.168.99.101 --file talos/controlplane/controlplane-01.yaml
```

### Managing Applications with Flux

```bash
# Deploy new application
# 1. Add manifests to kubernetes/apps/<app-name>/
# 2. Commit and push to Git
# 3. Flux automatically deploys

# Force reconciliation
flux reconcile kustomization <name>

# Suspend/resume reconciliation
flux suspend kustomization <name>
flux resume kustomization <name>
```

---

## Repository Structure

```
.
├── scripts/                     # Automation scripts
│   ├── download-talos-images.sh # Download node images from factory
│   ├── generate-configs.sh      # Generate Talos configurations
│   ├── apply-configs.sh         # Apply configs to nodes
│   └── bootstrap.sh             # Bootstrap cluster
│
├── talos/                       # Talos configuration
│   ├── secrets.yaml             # Cluster secrets (gitignored)
│   ├── talosconfig              # Talos API config (gitignored)
│   ├── controlplane.yaml        # Base control plane config
│   ├── worker.yaml              # Base worker config
│   ├── controlplane/            # Control plane node configs
│   │   ├── *-patch.yaml         # Node-specific patches (committed)
│   │   └── *.yaml               # Generated configs (gitignored)
│   └── worker/                  # Worker node configs
│       ├── *-patch.yaml         # Node-specific patches (committed)
│       └── *.yaml               # Generated configs (gitignored)
│
├── kubernetes/                  # Kubernetes manifests
│   ├── flux/                    # Flux GitOps configuration
│   │   └── flux-system/         # Flux system components
│   ├── infrastructure/          # Core infrastructure services
│   │   ├── metallb/             # MetalLB load balancer configs
│   │   │   ├── namespace.yaml
│   │   │   ├── ip-pool.yaml     # IP address pool (192.168.99.120-140)
│   │   │   └── l2-advertisement.yaml
│   │   └── traefik/             # Traefik ingress controller
│   │       ├── namespace.yaml
│   │       ├── helm-repository.yaml
│   │       └── helm-release.yaml
│   └── apps/                    # Application deployments
│       └── (your apps here)
│
├── .gitignore                   # Git ignore rules
└── README.md                    # This file
```

### Key Files

- **talos/secrets.yaml**: Cluster certificates and tokens (sensitive, gitignored)
- **talos/talosconfig**: Talos API credentials (sensitive, gitignored)
- **kubeconfig**: Kubernetes API credentials (sensitive, gitignored)
- **kubernetes/flux/flux-system/**: Flux configuration (auto-generated by Flux)

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

- **Documentation**: 
  - [Talos Docs](https://www.talos.dev/)
  - [Flux Docs](https://fluxcd.io/)
  - [MetalLB Docs](https://metallb.universe.tf/)
  - [Traefik Docs](https://doc.traefik.io/traefik/)
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