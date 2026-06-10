#!/usr/bin/env bash
# kernel-tune-ai.sh
#
# Open AI OS / VaaniAI kernel tuning framework.
# Default mode is DRY-RUN. Use --apply to make changes.
#
# Compatibility wrapper for old behavior:
#   exec /usr/local/ipcs/buildtools/kernel-tune-ai.sh --apply --profile=inference "$@"

set -euo pipefail

VERSION="1.0.0"

STATE_DIR="/var/lib/kernel-tune-ai"
BACKUP_DIR="${STATE_DIR}/backup"
LOG_FILE="${STATE_DIR}/kernel-tune-ai.log"

SYSCTL_CONF="/etc/sysctl.d/99-aios.conf"
HUGEPAGES_CONF="/etc/sysctl.d/99-aios-hugepages.conf"
MODULE_BLACKLIST_CONF="/etc/modprobe.d/openaios-blacklist.conf"
NVIDIA_MODPROBE_CONF="/etc/modprobe.d/nvidia-ai.conf"
SYSTEMD_CONF="/etc/systemd/system.conf"
THP_SERVICE="/etc/systemd/system/aios-thp.service"
UDEV_IO_RULES="/etc/udev/rules.d/60-aios-io-scheduler.rules"
GRUB_DEFAULT="/etc/default/grub"

PROFILE="balanced"
PLATFORM="auto"
MODE="dry-run"

APPLY=0
STATUS=0
REVERT=0
STRIP_MODULES=1
SKIP_MODULES=0
SKIP_GRUB=0
SKIP_GPU=0
SKIP_SYSTEMD=0
SKIP_SYSCTL=0
SKIP_HUGEPAGES=0
BUILD_KERNEL=0

HUGEPAGES_2M="auto"
HUGEPAGES_1G="0"

KERNEL_SRC=""
KERNEL_OUTPUT_DIR="./kernel-ai-rpms"
KERNEL_LOCALVERSION="-ai"

KEEP_MODULES=()
EXTRA_GRUB_PARAMS=()

DETECTED_PLATFORM="generic"
DETECTED_GPU="none"
TOTAL_CORES="$(nproc 2>/dev/null || echo 1)"
ISOLATE_FROM=""
ISOLATE_TO=""

mkdir -p "${STATE_DIR}" "${BACKUP_DIR}" 2>/dev/null || true

log() {
    local msg="$*"
    echo "[$(date '+%F %T')] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

info() { echo "INFO: $*"; log "INFO: $*"; }
warn() { echo "WARN: $*" >&2; log "WARN: $*"; }
die() { echo "ERROR: $*" >&2; log "ERROR: $*"; exit 1; }

usage() {
    cat <<'USAGE'
Usage: kernel-tune-ai.sh [OPTIONS]

Runtime:
  --apply                   Apply changes. Without this, dry-run is used.
  --dry-run                 Show actions only. Default.
  --status                  Show current tuning state.
  --revert                  Restore files from /var/lib/kernel-tune-ai/backup.

Profiles:
  --profile=balanced        balanced | inference | training
                            balanced  = safe default for mixed workloads
                            inference = low-latency serving / VaaniAI voice
                            training  = throughput / checkpoint / data pipeline

Platform:
  --platform=auto           auto | generic | vmware | dell | aws | azure | gcp

Hugepages:
  --hugepages=COUNT         Number of 2MB hugepages. Default: auto.
  --hugepages-1g=COUNT      Number of 1GB hugepages via GRUB. Default: 0.

Modules:
  --strip-modules           Blacklist unused modules. Default.
  --skip-modules            Do not generate module blacklist.
  --keep-module=NAME        Prevent a module from being blacklisted.

GPU:
  --skip-gpu                Do not apply GPU tuning.
  --gpu-persistence         Alias; NVIDIA persistence is enabled when supported.

GRUB:
  --skip-grub               Do not update /etc/default/grub.
  --extra-grub-param=PARAM  Append additional kernel boot parameter.

System:
  --skip-systemd            Do not update systemd limits.
  --skip-sysctl             Do not write sysctl configuration.
  --skip-hugepages          Do not configure hugepages/THP.

Kernel Build:
  --build-kernel            Generate stripped kernel config/build framework notes.
  --kernel-src=PATH         Kernel source directory or .src.rpm.
  --kernel-output-dir=DIR   Output directory for kernel RPMs.
  --kernel-localversion=V   Local version suffix. Default: -ai.

Other:
  -h, --help                Show help.
  --version                 Show version.

Examples:
  ./kernel-tune-ai.sh --profile=inference
  sudo ./kernel-tune-ai.sh --apply --profile=inference
  sudo ./kernel-tune-ai.sh --apply --profile=training --hugepages=32768 --hugepages-1g=8
  sudo ./kernel-tune-ai.sh --apply --platform=vmware
  sudo ./kernel-tune-ai.sh --revert
  ./kernel-tune-ai.sh --status
USAGE
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --apply) APPLY=1; MODE="apply"; shift ;;
            --dry-run) APPLY=0; MODE="dry-run"; shift ;;
            --status) STATUS=1; shift ;;
            --revert) REVERT=1; shift ;;
            --profile=*) PROFILE="${1#*=}"; shift ;;
            --platform=*) PLATFORM="${1#*=}"; shift ;;
            --hugepages=*) HUGEPAGES_2M="${1#*=}"; shift ;;
            --hugepages-1g=*) HUGEPAGES_1G="${1#*=}"; shift ;;
            --strip-modules) STRIP_MODULES=1; SKIP_MODULES=0; shift ;;
            --skip-modules) SKIP_MODULES=1; shift ;;
            --keep-module=*) KEEP_MODULES+=("${1#*=}"); shift ;;
            --skip-grub) SKIP_GRUB=1; shift ;;
            --skip-gpu) SKIP_GPU=1; shift ;;
            --gpu-persistence) shift ;;
            --skip-systemd) SKIP_SYSTEMD=1; shift ;;
            --skip-sysctl) SKIP_SYSCTL=1; shift ;;
            --skip-hugepages) SKIP_HUGEPAGES=1; shift ;;
            --extra-grub-param=*) EXTRA_GRUB_PARAMS+=("${1#*=}"); shift ;;
            --build-kernel) BUILD_KERNEL=1; shift ;;
            --kernel-src=*) KERNEL_SRC="${1#*=}"; shift ;;
            --kernel-output-dir=*) KERNEL_OUTPUT_DIR="${1#*=}"; shift ;;
            --kernel-localversion=*) KERNEL_LOCALVERSION="${1#*=}"; shift ;;
            --version) echo "${VERSION}"; exit 0 ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    case "${PROFILE}" in balanced|inference|training) ;; *) die "Invalid --profile=${PROFILE}" ;; esac
    case "${PLATFORM}" in auto|generic|vmware|dell|aws|azure|gcp) ;; *) die "Invalid --platform=${PLATFORM}" ;; esac
}

need_root_for_apply() {
    if [[ "${APPLY}" -eq 1 || "${REVERT}" -eq 1 || "${BUILD_KERNEL}" -eq 1 ]]; then
        [[ "${EUID}" -eq 0 ]] || die "Run as root for --apply, --revert, or --build-kernel."
    fi
}

backup_file() {
    local file="$1"
    [[ -e "${file}" ]] || return 0
    local safe dst
    safe="$(echo "${file}" | sed 's#/#_#g')"
    dst="${BACKUP_DIR}/${safe}.$(date '+%Y%m%d%H%M%S')"
    cp -a "${file}" "${dst}"
    info "Backed up ${file} to ${dst}"
}

write_file() {
    local file="$1"
    local content="$2"
    if [[ "${APPLY}" -eq 1 ]]; then
        backup_file "${file}"
        mkdir -p "$(dirname "${file}")"
        printf "%s\n" "${content}" > "${file}"
        info "Wrote ${file}"
    else
        echo "DRY-RUN: write ${file}"
        echo "--------- ${file} ---------"
        printf "%s\n" "${content}"
        echo "---------------------------"
    fi
}

run_cmd() {
    local cmd="$*"
    if [[ "${APPLY}" -eq 1 ]]; then
        info "RUN: ${cmd}"
        eval "${cmd}"
    else
        echo "DRY-RUN: ${cmd}"
    fi
}

detect_platform() {
    if [[ "${PLATFORM}" != "auto" ]]; then
        DETECTED_PLATFORM="${PLATFORM}"
        return
    fi
    local product manufacturer chassis uuid
    product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
    manufacturer="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || cat /sys/class/dmi/id/board_vendor 2>/dev/null || true)"
    chassis="$(cat /sys/class/dmi/id/chassis_asset_tag 2>/dev/null || true)"
    uuid="$(cat /sys/hypervisor/uuid 2>/dev/null || true)"

    if echo "${product}" | grep -qi "VMware"; then DETECTED_PLATFORM="vmware"
    elif echo "${uuid}" | grep -qi '^ec2'; then DETECTED_PLATFORM="aws"
    elif echo "${product}" | grep -qi "Google Compute Engine"; then DETECTED_PLATFORM="gcp"
    elif echo "${chassis}" | grep -q "7783-7084-3265-9085-8269-3286-77"; then DETECTED_PLATFORM="azure"
    elif echo "${manufacturer}" | grep -qi "Dell"; then DETECTED_PLATFORM="dell"
    else DETECTED_PLATFORM="generic"
    fi
}

detect_gpu() {
    if command -v lspci >/dev/null 2>&1; then
        if lspci | grep -qi "NVIDIA"; then DETECTED_GPU="nvidia"
        elif lspci | grep -Eqi "AMD|Advanced Micro Devices.*(VGA|Display|3D)"; then DETECTED_GPU="amd"
        elif lspci | grep -Eqi "Intel.*(VGA|Display|3D|Gaudi)"; then DETECTED_GPU="intel"
        else DETECTED_GPU="none"
        fi
    else
        DETECTED_GPU="unknown"
    fi
}

calculate_hugepages_2m() {
    if [[ "${HUGEPAGES_2M}" != "auto" ]]; then echo "${HUGEPAGES_2M}"; return; fi
    local mem_kb pages
    mem_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    if [[ "${PROFILE}" == "training" ]]; then pages=$(( mem_kb / 2 / 2048 )); else pages=$(( mem_kb / 4 / 2048 )); fi
    if [[ "${pages}" -lt 4096 && "${mem_kb}" -ge $((16 * 1024 * 1024)) ]]; then pages=4096; fi
    echo "${pages}"
}

sysctl_content() {
    local hp2m dirty_ratio dirty_bg
    hp2m="$(calculate_hugepages_2m)"
    case "${PROFILE}" in
        inference) dirty_ratio=10; dirty_bg=5 ;;
        training) dirty_ratio=40; dirty_bg=10 ;;
        balanced) dirty_ratio=20; dirty_bg=10 ;;
    esac
    [[ "${DETECTED_PLATFORM}" == "vmware" ]] && dirty_bg=5
    cat <<EOF2
# Open AI OS / VaaniAI kernel tuning for AI workloads
# Generated by kernel-tune-ai.sh
# Profile: ${PROFILE}
# Platform: ${DETECTED_PLATFORM}

# Memory: keep model weights in RAM and reduce allocation stalls.
vm.swappiness = 1
vm.dirty_ratio = ${dirty_ratio}
vm.dirty_background_ratio = ${dirty_bg}
vm.overcommit_memory = 1
vm.min_free_kbytes = 1048576
vm.zone_reclaim_mode = 0
vm.max_map_count = 1048576
kernel.numa_balancing = 0

# Hugepages: 2MB pages for LLM inference, embeddings, and pinned buffers.
vm.nr_hugepages = ${hp2m}

# Network: distributed inference/training and high-throughput model serving.
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.netdev_max_backlog = 50000
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fin_timeout = 15
net.core.optmem_max = 67108864
$( [[ "${DETECTED_PLATFORM}" == "aws" ]] && echo "net.core.netdev_budget = 600" || true )

# File descriptors / IPC / data pipeline scaling.
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576
fs.aio-max-nr = 1048576
kernel.pid_max = 4194304
kernel.threads-max = 4194304
EOF2
}

write_sysctl_config() {
    [[ "${SKIP_SYSCTL}" -eq 1 ]] && { info "Skipping sysctl."; return; }
    write_file "${SYSCTL_CONF}" "$(sysctl_content)"
    if [[ "${APPLY}" -eq 1 ]]; then sysctl --system || warn "sysctl --system returned non-zero."; else echo "DRY-RUN: sysctl --system"; fi
}

write_thp_service() {
    [[ "${SKIP_HUGEPAGES}" -eq 1 ]] && { info "Skipping THP service."; return; }
    local thp_mode thp_defrag content
    case "${PROFILE}" in training) thp_mode="always" ;; *) thp_mode="madvise" ;; esac
    thp_defrag="defer+madvise"
    content="$(cat <<EOF2
[Unit]
Description=Configure Transparent Huge Pages for Open AI OS AI workloads
After=sysinit.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo ${thp_mode} > /sys/kernel/mm/transparent_hugepage/enabled; echo ${thp_defrag} > /sys/kernel/mm/transparent_hugepage/defrag || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF2
)"
    write_file "${THP_SERVICE}" "${content}"
    if [[ "${APPLY}" -eq 1 ]]; then
        systemctl daemon-reload || true
        systemctl enable aios-thp.service || true
        echo "${thp_mode}" > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
        echo "${thp_defrag}" > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
    else
        echo "DRY-RUN: systemctl daemon-reload && systemctl enable aios-thp.service"
    fi
}

write_systemd_limits() {
    [[ "${SKIP_SYSTEMD}" -eq 1 ]] && { info "Skipping systemd limits."; return; }
    local existing content
    existing="$(cat "${SYSTEMD_CONF}" 2>/dev/null || echo '[Manager]')"
    existing="$(printf "%s\n" "${existing}" | grep -Ev '^(DefaultLimitNOFILE|DefaultLimitMEMLOCK|DefaultLimitNPROC|DefaultTasksMax|DefaultLimitCORE)=' || true)"
    content="$(cat <<EOF2
${existing}

# Open AI OS AI workload limits
DefaultLimitNOFILE=1048576:1048576
DefaultLimitMEMLOCK=infinity
DefaultLimitNPROC=infinity
DefaultTasksMax=infinity
DefaultLimitCORE=0:0
EOF2
)"
    write_file "${SYSTEMD_CONF}" "${content}"
}

write_io_scheduler_rules() {
    local content
    content="$(cat <<'EOF2'
# Open AI OS IO scheduler rules for AI workloads.
ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd*", ATTR{queue/scheduler}="mq-deadline"
EOF2
)"
    write_file "${UDEV_IO_RULES}" "${content}"
    if [[ "${APPLY}" -eq 1 ]]; then
        for dev in /sys/block/nvme*; do [[ -d "${dev}" ]] && echo none > "${dev}/queue/scheduler" 2>/dev/null || true; done
        udevadm control --reload-rules 2>/dev/null || true
    else
        echo "DRY-RUN: set NVMe scheduler to none and reload udev rules"
    fi
}

derive_cpu_isolation() {
    if [[ "${TOTAL_CORES}" -gt 8 ]]; then ISOLATE_FROM=4; ISOLATE_TO=$((TOTAL_CORES - 1)); else ISOLATE_FROM=""; ISOLATE_TO=""; fi
}

grub_params() {
    derive_cpu_isolation
    local hp2m thp_param cstate_param idle_param audit_param params p
    hp2m="$(calculate_hugepages_2m)"
    case "${PROFILE}" in
        inference) thp_param="transparent_hugepage=madvise"; cstate_param="processor.max_cstate=1 intel_idle.max_cstate=0"; idle_param="idle=poll"; audit_param="audit=0" ;;
        training) thp_param="transparent_hugepage=always"; cstate_param="processor.max_cstate=1 intel_idle.max_cstate=0"; idle_param=""; audit_param="audit=0" ;;
        balanced) thp_param="transparent_hugepage=madvise"; cstate_param="processor.max_cstate=1 intel_idle.max_cstate=0"; idle_param=""; audit_param="" ;;
    esac
    params="default_hugepagesz=2M hugepagesz=2M hugepages=${hp2m} ${thp_param} ${cstate_param} iommu=pt pci=realloc"
    [[ "${HUGEPAGES_1G}" != "0" ]] && params="${params} hugepagesz=1G hugepages=${HUGEPAGES_1G}"
    [[ -n "${ISOLATE_FROM}" ]] && params="${params} isolcpus=${ISOLATE_FROM}-${ISOLATE_TO} nohz_full=${ISOLATE_FROM}-${ISOLATE_TO} rcu_nocbs=${ISOLATE_FROM}-${ISOLATE_TO}"
    [[ -n "${idle_param}" ]] && params="${params} ${idle_param}"
    [[ -n "${audit_param}" ]] && params="${params} ${audit_param}"
    case "${DETECTED_PLATFORM}" in vmware) params="${params} elevator=none" ;; aws|azure|gcp) params="${params} console=ttyS0" ;; esac
    for p in "${EXTRA_GRUB_PARAMS[@]}"; do params="${params} ${p}"; done
    echo "${params}" | xargs
}

update_grub_config() {
    [[ "${SKIP_GRUB}" -eq 1 ]] && { info "Skipping GRUB."; return; }
    [[ -f "${GRUB_DEFAULT}" ]] || { warn "${GRUB_DEFAULT} not found; skipping GRUB update."; return; }
    local params
    params="$(grub_params)"
    if [[ "${APPLY}" -eq 1 ]]; then
        backup_file "${GRUB_DEFAULT}"
        python3 - "${GRUB_DEFAULT}" "${params}" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
new_params = sys.argv[2].split()
text = path.read_text()
m = re.search(r'^(GRUB_CMDLINE_LINUX=)"(.*)"', text, flags=re.M)
if not m:
    text += '\nGRUB_CMDLINE_LINUX=""\n'
    m = re.search(r'^(GRUB_CMDLINE_LINUX=)"(.*)"', text, flags=re.M)
existing = m.group(2).split()
merged = existing[:]
for p in new_params:
    key = p.split('=', 1)[0]
    merged = [x for x in merged if x.split('=', 1)[0] != key]
    merged.append(p)
replacement = f'{m.group(1)}"' + ' '.join(merged) + '"'
text = text[:m.start()] + replacement + text[m.end():]
path.write_text(text)
PY
        if command -v update-grub >/dev/null 2>&1; then update-grub || true
        elif command -v grub2-mkconfig >/dev/null 2>&1; then
            if [[ -d /sys/firmware/efi ]]; then grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg 2>/dev/null || grub2-mkconfig -o /boot/grub2/grub.cfg || true
            else grub2-mkconfig -o /boot/grub2/grub.cfg || true
            fi
        else warn "No update-grub or grub2-mkconfig found."
        fi
    else
        echo "DRY-RUN: add GRUB params to ${GRUB_DEFAULT}: ${params}"
    fi
}

is_kept_module() {
    local mod="$1" keep
    for keep in "${KEEP_MODULES[@]}"; do [[ "${mod}" == "${keep}" ]] && return 0; done
    case "${DETECTED_PLATFORM}" in
        vmware) [[ "${mod}" =~ ^(vmw_balloon|vmxnet3|vmw_pvscsi)$ ]] && return 0 ;;
        azure) [[ "${mod}" =~ ^(hv_vmbus|hv_netvsc|hv_storvsc|hv_utils)$ ]] && return 0 ;;
        aws) [[ "${mod}" =~ ^(ena|nvme|nvme_core)$ ]] && return 0 ;;
        gcp) [[ "${mod}" =~ ^(gve|virtio_net|virtio_blk|virtio_pci)$ ]] && return 0 ;;
    esac
    return 1
}

write_module_blacklist() {
    [[ "${SKIP_MODULES}" -eq 1 ]] && { info "Skipping module blacklist."; return; }
    [[ "${STRIP_MODULES}" -eq 1 ]] || return
    local modules=(bluetooth btusb iwlwifi cfg80211 rfkill atm can dccp sctp tipc rds appletalk ipx psnap p8022 floppy pata_acpi snd soundcore pcspkr firewire-core uvcvideo cramfs freevxfs hfs hfsplus jffs2 squashfs udf parport parport_pc vmw_balloon vmxnet3 vmw_pvscsi hv_vmbus hv_netvsc hv_storvsc hv_utils ena gve)
    local content mod
    content="# Open AI OS module blacklist for AI appliance/server profile
# Generated by kernel-tune-ai.sh
# Platform-aware keep rules applied for: ${DETECTED_PLATFORM}
"
    for mod in "${modules[@]}"; do
        if is_kept_module "${mod}"; then content+=$'\n'"# keep ${mod} for ${DETECTED_PLATFORM}"
        else content+=$'\n'"blacklist ${mod}"$'\n'"install ${mod} /bin/true"
        fi
    done
    write_file "${MODULE_BLACKLIST_CONF}" "${content}"
}

tune_gpu() {
    [[ "${SKIP_GPU}" -eq 1 ]] && { info "Skipping GPU tuning."; return; }
    case "${DETECTED_GPU}" in
        nvidia)
            write_file "${NVIDIA_MODPROBE_CONF}" "# Open AI OS NVIDIA tuning.
options nvidia NVreg_UsePageAttributeTable=1
options nvidia NVreg_RegistryDwords=\"RMUseSwI2c=0x01;RMI2cSpeed=100\""
            if command -v nvidia-smi >/dev/null 2>&1; then run_cmd "nvidia-smi -pm 1 || true"; else info "nvidia-smi not found; persistence mode not applied."; fi
            if command -v setpci >/dev/null 2>&1 && command -v lspci >/dev/null 2>&1; then
                while read -r dev; do [[ -n "${dev}" ]] || continue; [[ "${APPLY}" -eq 1 ]] && setpci -s "${dev}" CAP_EXP+8.w=2936 2>/dev/null || echo "DRY-RUN: set PCIe MaxReadReq hint for NVIDIA device ${dev}"; done < <(lspci -D | awk '/NVIDIA/ {print $1}')
            fi
            ;;
        amd) info "AMD GPU detected. ROCm-specific tuning hooks can be added here." ;;
        intel) info "Intel accelerator/GPU detected. oneAPI/OpenVINO-specific tuning hooks can be added here." ;;
        *) info "No GPU tuning applied. GPU=${DETECTED_GPU}" ;;
    esac
}

status_report() {
    detect_platform; detect_gpu
    local hp2m recommended_thp current_thp current_swappiness current_hp
    hp2m="$(calculate_hugepages_2m)"
    [[ "${PROFILE}" == "training" ]] && recommended_thp="always" || recommended_thp="madvise"
    current_thp="$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo unknown)"
    current_swappiness="$(sysctl -n vm.swappiness 2>/dev/null || echo unknown)"
    current_hp="$(sysctl -n vm.nr_hugepages 2>/dev/null || echo unknown)"
    cat <<EOF2
Open AI OS Kernel Tuning Status
--------------------------------
Version:              ${VERSION}
Profile:              ${PROFILE}
Detected platform:    ${DETECTED_PLATFORM}
Detected GPU:         ${DETECTED_GPU}
CPU cores:            ${TOTAL_CORES}

Swappiness:
  Current:             ${current_swappiness}
  Recommended:         1

HugePages 2MB:
  Current:             ${current_hp}
  Recommended:         ${hp2m}

Transparent HugePages:
  Current:             ${current_thp}
  Recommended:         ${recommended_thp}

Files:
  Sysctl config:        ${SYSCTL_CONF} $( [[ -f "${SYSCTL_CONF}" ]] && echo "[present]" || echo "[missing]" )
  Module blacklist:     ${MODULE_BLACKLIST_CONF} $( [[ -f "${MODULE_BLACKLIST_CONF}" ]] && echo "[present]" || echo "[missing]" )
  NVIDIA config:        ${NVIDIA_MODPROBE_CONF} $( [[ -f "${NVIDIA_MODPROBE_CONF}" ]] && echo "[present]" || echo "[missing]" )
  THP service:          ${THP_SERVICE} $( [[ -f "${THP_SERVICE}" ]] && echo "[present]" || echo "[missing]" )
EOF2
}

revert_changes() {
    [[ -d "${BACKUP_DIR}" ]] || die "Backup directory not found: ${BACKUP_DIR}"
    local files=("${SYSCTL_CONF}" "${HUGEPAGES_CONF}" "${MODULE_BLACKLIST_CONF}" "${NVIDIA_MODPROBE_CONF}" "${SYSTEMD_CONF}" "${THP_SERVICE}" "${UDEV_IO_RULES}" "${GRUB_DEFAULT}")
    local file safe latest
    for file in "${files[@]}"; do
        safe="$(echo "${file}" | sed 's#/#_#g')"
        latest="$(ls -1t "${BACKUP_DIR}/${safe}".* 2>/dev/null | head -1 || true)"
        if [[ -n "${latest}" ]]; then mkdir -p "$(dirname "${file}")"; cp -a "${latest}" "${file}"; info "Restored ${file} from ${latest}"; fi
    done
    systemctl daemon-reload 2>/dev/null || true
    info "Revert complete. Regenerate GRUB manually if required."
}

build_kernel_framework() {
    info "Kernel build framework selected."
    mkdir -p "${KERNEL_OUTPUT_DIR}" 2>/dev/null || true
    cat <<EOF2
Kernel build requested
----------------------
Source:         ${KERNEL_SRC:-auto-detect}
Output dir:     ${KERNEL_OUTPUT_DIR}
Local version:  ${KERNEL_LOCALVERSION}

Framework included. Production build flow should:
  1. Validate kernel source directory or install SRPM.
  2. Copy /boot/config-$(uname -r) to build .config.
  3. Disable unused subsystems: Bluetooth, wireless, sound, legacy protocols, floppy/IDE, FireWire, ISDN, staging.
  4. Keep AI-critical subsystems: THP, HugeTLB, cgroups, VFIO, NUMA, BPF/JIT, perf, NVMe, DRM.
  5. Build RPM with local version ${KERNEL_LOCALVERSION}.
EOF2
    if [[ "${APPLY}" -eq 1 ]]; then
        cat > "${KERNEL_OUTPUT_DIR}/kernel-ai-build-notes.txt" <<EOF2
Kernel build framework generated by kernel-tune-ai.sh.
Source: ${KERNEL_SRC:-auto-detect}
Local version: ${KERNEL_LOCALVERSION}
EOF2
        info "Wrote ${KERNEL_OUTPUT_DIR}/kernel-ai-build-notes.txt"
    fi
}

apply_all() {
    detect_platform; detect_gpu
    info "Mode: ${MODE}"
    info "Profile: ${PROFILE}"
    info "Platform: ${DETECTED_PLATFORM}"
    info "GPU: ${DETECTED_GPU}"
    write_sysctl_config
    write_thp_service
    write_systemd_limits
    write_io_scheduler_rules
    write_module_blacklist
    tune_gpu
    update_grub_config
    [[ "${BUILD_KERNEL}" -eq 1 ]] && build_kernel_framework
    if [[ "${APPLY}" -eq 1 ]]; then info "Tuning applied. Reboot is recommended for GRUB, hugepages, CPU isolation, and module blacklist changes."; else info "Dry-run complete. Re-run with --apply to modify the system."; fi
}

main() {
    parse_args "$@"
    need_root_for_apply
    if [[ "${STATUS}" -eq 1 ]]; then status_report; exit 0; fi
    if [[ "${REVERT}" -eq 1 ]]; then revert_changes; exit 0; fi
    apply_all
}

main "$@"
