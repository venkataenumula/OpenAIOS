#!/usr/bin/env bash
# 03-kernel-tuning.sh
# Backward-compatible wrapper for the new Open AI OS kernel tuning framework.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "${SCRIPT_DIR}/kernel-tune-ai.sh" ]]; then
    exec "${SCRIPT_DIR}/kernel-tune-ai.sh" --apply --profile=inference "$@"
elif [[ -x "/usr/local/ipcs/buildtools/kernel-tune-ai.sh" ]]; then
    exec "/usr/local/ipcs/buildtools/kernel-tune-ai.sh" --apply --profile=inference "$@"
elif [[ -x "/usr/local/ipcs/icu/buildtools/kernel-tune-ai.sh" ]]; then
    exec "/usr/local/ipcs/icu/buildtools/kernel-tune-ai.sh" --apply --profile=inference "$@"
else
    echo "ERROR: kernel-tune-ai.sh not found." >&2
    exit 1
fi
