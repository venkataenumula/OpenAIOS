#!/usr/bin/env bash
set -euo pipefail

BASE_CONFIG=${1:-/boot/config-$(uname -r)}
PROFILE=${2:-edge}
OUT=${3:-.config.openaios}

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
COMMON="$ROOT_DIR/configs/openaios.config"
PROFILE_FILE="$ROOT_DIR/configs/openaios-${PROFILE}.config"

if [[ ! -f "$BASE_CONFIG" ]]; then
  echo "ERROR: base config not found: $BASE_CONFIG" >&2
  exit 1
fi
if [[ ! -f "$PROFILE_FILE" ]]; then
  echo "ERROR: profile config not found: $PROFILE_FILE" >&2
  echo "Valid profiles: edge, enterprise, appliance" >&2
  exit 1
fi

cp "$BASE_CONFIG" "$OUT"

apply_fragment() {
  local fragment=$1
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    local key=${line%%=*}
    if grep -qE "^${key}=|^# ${key} is not set" "$OUT"; then
      sed -i -E "s|^${key}=.*|${line}|; s|^# ${key} is not set|${line}|" "$OUT"
    else
      echo "$line" >> "$OUT"
    fi
  done < "$fragment"
}

apply_fragment "$COMMON"
apply_fragment "$PROFILE_FILE"

echo "Generated $OUT using profile=$PROFILE"
echo "Next: copy it into the Debian kernel source tree as .config and run: make olddefconfig"
