#!/usr/bin/env bash
# 04-gpu-setup.sh — Install NVIDIA drivers, CUDA toolkit, and enable
# GPUDirect Storage for AI workloads.
# Run as root. Supports Ubuntu 22.04/24.04.

set -euo pipefail

echo "==> Setting up GPU stack..."

# ── Detect GPU vendor ───────────────────────────────────────────
if lspci | grep -qi nvidia; then
    GPU_VENDOR="nvidia"
elif lspci | grep -qi "amd.*radeon\|amd.*instinct"; then
    GPU_VENDOR="amd"
else
    echo "  No supported GPU detected. Skipping GPU setup."
    exit 0
fi

echo "  Detected GPU vendor: ${GPU_VENDOR}"

# ── NVIDIA Setup ────────────────────────────────────────────────
if [ "${GPU_VENDOR}" = "nvidia" ]; then

    # Install NVIDIA driver + CUDA keyring
    if ! command -v nvidia-smi &>/dev/null; then
        echo "  Installing NVIDIA drivers and CUDA toolkit..."

        apt-get install -y linux-headers-$(uname -r) build-essential

        # Add NVIDIA CUDA repo
        DISTRO=$(. /etc/os-release && echo "${ID}${VERSION_ID}" | tr -d '.')
        ARCH=$(dpkg --print-architecture)
        wget -qO /tmp/cuda-keyring.deb \
            "https://developer.download.nvidia.com/compute/cuda/repos/${DISTRO}/${ARCH}/cuda-keyring_1.1-1_all.deb"
        dpkg -i /tmp/cuda-keyring.deb
        rm -f /tmp/cuda-keyring.deb
        apt-get update

        apt-get install -y cuda-toolkit nvidia-driver-560
    else
        echo "  NVIDIA driver already installed: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
    fi

    # NVIDIA Container Toolkit (for Docker GPU access)
    if ! command -v nvidia-ctk &>/dev/null; then
        echo "  Installing NVIDIA Container Toolkit..."
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
            | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
            | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' \
            > /etc/apt/sources.list.d/nvidia-container-toolkit.list
        apt-get update
        apt-get install -y nvidia-container-toolkit
        nvidia-ctk runtime configure --runtime=docker
        systemctl restart docker 2>/dev/null || true
    fi

    # GPU persistence mode — keeps GPU initialized between jobs
    echo "  Enabling GPU persistence mode..."
    nvidia-smi -pm 1 2>/dev/null || true

    # GPUDirect Storage
    echo "  Configuring GPUDirect Storage..."
    if apt-cache show nvidia-gds &>/dev/null 2>&1; then
        apt-get install -y nvidia-gds || true
    fi

    # Set GPU compute mode to DEFAULT (shared) for multi-service use
    nvidia-smi -c DEFAULT 2>/dev/null || true

    # Persist GPU settings via systemd
    cat > /etc/systemd/system/aios-gpu.service <<'EOF'
[Unit]
Description=NVIDIA GPU persistence and tuning for AI workloads
After=nvidia-persistenced.service

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -pm 1
ExecStart=/usr/bin/nvidia-smi -c DEFAULT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable aios-gpu.service

    echo "  NVIDIA GPU stack installed."
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader

fi

# ── AMD ROCm Setup ──────────────────────────────────────────────
if [ "${GPU_VENDOR}" = "amd" ]; then
    echo "  Installing AMD ROCm stack..."

    if ! command -v rocm-smi &>/dev/null; then
        apt-get install -y wget gnupg2
        wget -qO - https://repo.radeon.com/rocm/rocm.gpg.key | apt-key add -
        ROCM_VERSION="6.1"
        echo "deb [arch=amd64] https://repo.radeon.com/rocm/apt/${ROCM_VERSION}/ ubuntu main" \
            > /etc/apt/sources.list.d/rocm.list
        apt-get update
        apt-get install -y rocm-dev rocm-libs
    fi

    echo "  AMD ROCm stack installed."
    rocm-smi --showproductname 2>/dev/null || true
fi

echo "==> GPU setup complete."
