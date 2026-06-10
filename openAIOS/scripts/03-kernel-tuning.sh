#!/usr/bin/env bash
# 03-kernel-tuning.sh — Kernel and sysctl tuning for AI workloads:
# memory, IO, hugepages, NUMA, CPU isolation.
# Run as root.

set -euo pipefail

SYSCTL_CONF="/etc/sysctl.d/99-aios.conf"
GRUB_CONF="/etc/default/grub"

echo "==> Applying kernel tuning for AI workloads..."

# ── Sysctl: Memory Optimizations ────────────────────────────────
cat > "${SYSCTL_CONF}" <<'EOF'
# VaaniAI AI OS — kernel tuning for AI workloads

# Memory: avoid swapping model weights to disk
vm.swappiness = 1
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5

# Hugepages: pre-allocate for LLM inference and embeddings
# Adjust nr_hugepages based on available RAM and model size.
# Each hugepage = 2MB. 4096 pages = 8GB reserved for AI models.
vm.nr_hugepages = 4096

# Transparent Huge Pages: let the kernel merge pages automatically
# (also enabled via /sys below for boot-time reliability)

# Network: tuning for high-throughput model serving
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

# File descriptors: model servers open many files
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
EOF

sysctl --system

# ── Transparent Huge Pages ──────────────────────────────────────
echo "  Enabling Transparent Huge Pages..."
echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true

# Persist THP across reboots
cat > /etc/systemd/system/aios-thp.service <<'EOF'
[Unit]
Description=Enable Transparent Huge Pages for AI workloads
After=sysinit.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo always > /sys/kernel/mm/transparent_hugepage/enabled && echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable aios-thp.service

# ── CPU Isolation ───────────────────────────────────────────────
# Reserve cores 4+ for AI inference. Cores 0-3 handle OS and interrupts.
# Adjust based on your CPU topology (nproc, lscpu).
TOTAL_CORES=$(nproc)
if [ "${TOTAL_CORES}" -gt 8 ]; then
    ISOLATE_FROM=4
    ISOLATE_TO=$((TOTAL_CORES - 1))
    ISOLCPUS="isolcpus=${ISOLATE_FROM}-${ISOLATE_TO}"
    echo "  Configuring CPU isolation: cores ${ISOLATE_FROM}-${ISOLATE_TO} reserved for AI..."
else
    ISOLCPUS=""
    echo "  Skipping CPU isolation (only ${TOTAL_CORES} cores detected)."
fi

# ── NUMA Optimization ──────────────────────────────────────────
apt-get install -y numactl 2>/dev/null || true

# ── IO Scheduler: optimize for NVMe ────────────────────────────
echo "  Setting IO scheduler to 'none' for NVMe devices..."
for dev in /sys/block/nvme*; do
    if [ -d "${dev}" ]; then
        echo none > "${dev}/queue/scheduler" 2>/dev/null || true
    fi
done

# Persist IO scheduler
cat > /etc/udev/rules.d/60-aios-io-scheduler.rules <<'EOF'
ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd*", ATTR{queue/scheduler}="mq-deadline"
EOF

# ── GRUB: kernel boot parameters ───────────────────────────────
echo "  Updating GRUB with AI-optimized kernel parameters..."
GRUB_PARAMS="default_hugepagesz=2M hugepagesz=2M hugepages=4096"
GRUB_PARAMS="${GRUB_PARAMS} transparent_hugepage=always"
GRUB_PARAMS="${GRUB_PARAMS} processor.max_cstate=1 intel_idle.max_cstate=0"
GRUB_PARAMS="${GRUB_PARAMS} iommu=pt"
if [ -n "${ISOLCPUS}" ]; then
    GRUB_PARAMS="${GRUB_PARAMS} ${ISOLCPUS} nohz_full=${ISOLATE_FROM}-${ISOLATE_TO} rcu_nocbs=${ISOLATE_FROM}-${ISOLATE_TO}"
fi

if [ -f "${GRUB_CONF}" ]; then
    # Append to existing GRUB_CMDLINE_LINUX without duplicating
    if ! grep -q "hugepages=" "${GRUB_CONF}"; then
        sed -i "s/^GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"${GRUB_PARAMS} /" "${GRUB_CONF}"
        update-grub 2>/dev/null || grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
    fi
fi

echo "==> Kernel tuning applied. Reboot required for GRUB and hugepage changes."
