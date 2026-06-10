#!/usr/bin/env bash
# 07-agent-layer.sh — Deploy VaaniAI agent services (STT, Translation,
# LLM, TTS, Gateway) from the src/ directory.
# Run from the repository root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SRC_DIR="${REPO_ROOT}/src"

echo "==> Deploying VaaniAI agent layer..."

if [ ! -f "${SRC_DIR}/docker-compose.yml" ]; then
    echo "  ERROR: ${SRC_DIR}/docker-compose.yml not found."
    echo "  Run this script from the VaaniAI repository root."
    exit 1
fi

# ── Environment Setup ───────────────────────────────────────────
ENV_FILE="${SRC_DIR}/.env"
if [ ! -f "${ENV_FILE}" ]; then
    echo "  Creating .env from .env.example..."
    cp "${SRC_DIR}/.env.example" "${ENV_FILE}"
    echo ""
    echo "  *** IMPORTANT: Edit ${ENV_FILE} and set your OPENAI_API_KEY ***"
    echo "  (or switch to an on-prem LLM by modifying llm_service)"
    echo ""
fi

# ── Build and Start Services ───────────────────────────────────
echo "  Building and starting VaaniAI services..."
cd "${SRC_DIR}"
docker compose up --build -d

echo ""
echo "  Waiting for services to become healthy..."
TIMEOUT=120
ELAPSED=0
while [ "${ELAPSED}" -lt "${TIMEOUT}" ]; do
    HEALTHY=$(docker compose ps --format json 2>/dev/null \
        | grep -c '"healthy"' 2>/dev/null || echo "0")
    TOTAL=$(docker compose ps --format json 2>/dev/null \
        | wc -l 2>/dev/null || echo "0")

    if [ "${HEALTHY}" -ge "${TOTAL}" ] && [ "${TOTAL}" -gt 0 ]; then
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "  ... ${HEALTHY}/${TOTAL} services healthy (${ELAPSED}s)"
done

echo ""
docker compose ps

# ── Systemd Service for Auto-Start ─────────────────────────────
echo "  Creating systemd service for auto-start on boot..."
cat > /etc/systemd/system/vaaniai.service <<SVCEOF
[Unit]
Description=VaaniAI Agent Services
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${SRC_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable vaaniai.service

echo ""
echo "==> VaaniAI agent layer deployed."
echo ""
echo "Services:"
echo "  Gateway API:  POST http://localhost:8000/api/v1/vaaniai/chat"
echo "  Health check: GET  http://localhost:8000/health"
echo ""
echo "Configuration: ${ENV_FILE}"
echo "Logs:          cd ${SRC_DIR} && docker compose logs -f"
