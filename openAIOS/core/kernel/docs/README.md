# Open AI OS Kernel Starter Package

This package provides a starting point for a Debian-based Open AI OS kernel customization process.

## Contents

```text
configs/openaios.config              Common AI/container/GPU kernel config fragment
configs/openaios-edge.config         Small-footprint edge profile
configs/openaios-enterprise.config   Broad hardware/cloud/VM profile
configs/openaios-appliance.config    Aggressive appliance profile
scripts/merge-config.sh              Merge Debian config with Open AI OS fragments
scripts/build-debian-kernel.sh       Example Debian kernel build wrapper
scripts/install-module-blacklist.sh  Runtime module blacklist installer
modules/openaios_ai_core/            Safe placeholder out-of-tree kernel module
modules/openaios_model_cache/        Safe placeholder out-of-tree kernel module
```

## Recommended direction

Keep Open AI OS intelligence in userspace first:

- `openaios-gpud` for GPU inventory and allocation
- `openaios-schedulerd` for AI workload placement
- `openaios-modeld` for model lifecycle and cache management
- `openaios-observabilityd` for telemetry

Only move functionality into the kernel after clear performance, isolation, or security reasons are proven.

## Build kernel config

```bash
./scripts/merge-config.sh /boot/config-$(uname -r) edge .config.openaios
```

Profiles:

```text
edge
enterprise
appliance
```

## Build placeholder module

```bash
cd modules/openaios_ai_core
make
sudo insmod openaios_ai_core.ko
cat /proc/openaios_ai_core
sudo rmmod openaios_ai_core
```

## Safety note

The profile fragments are a starting point. Validate each option against the exact Debian kernel version and target hardware.
