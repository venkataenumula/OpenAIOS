#!/usr/bin/env bash
# 02-disable-services.sh — Disable unnecessary services for an AI appliance.
# Replaces firewalld with lean nftables rules.
# Run as root.

set -euo pipefail

echo "==> Disabling unnecessary services..."

SERVICES_TO_DISABLE=(
    cups cups-browsed
    postfix
    avahi-daemon
    rpcbind
    nfs-server nfs-kernel-server
    smbd nmbd
    ModemManager
    accounts-daemon
    packagekit
    snapd snapd.socket
    unattended-upgrades
    apport
    whoopsie
    kerneloops
    thermald
)

for svc in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl list-unit-files | grep -q "^${svc}"; then
        echo "  Disabling ${svc}..."
        systemctl stop "${svc}" 2>/dev/null || true
        systemctl disable "${svc}" 2>/dev/null || true
        systemctl mask "${svc}" 2>/dev/null || true
    fi
done

# Replace firewalld with lean nftables
if systemctl is-active --quiet firewalld 2>/dev/null; then
    echo "  Replacing firewalld with nftables..."
    systemctl stop firewalld
    systemctl disable firewalld
    systemctl mask firewalld
    apt-get install -y nftables
    systemctl enable nftables

    cat > /etc/nftables.conf <<'NFTEOF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        iif lo accept
        ct state established,related accept
        # SSH
        tcp dport 22 accept
        # VaaniAI gateway
        tcp dport 8000 accept
        # Health check (monolith)
        tcp dport 5005 accept
        # ICMP
        icmp type echo-request accept
        icmpv6 type { echo-request, nd-neighbor-solicit, nd-router-advert, nd-neighbor-advert } accept
    }
    chain forward {
        type filter hook forward priority 0; policy accept;
    }
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
NFTEOF
    nft -f /etc/nftables.conf
fi

echo "==> Unnecessary services disabled."
