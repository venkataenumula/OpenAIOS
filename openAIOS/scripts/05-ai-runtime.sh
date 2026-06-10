#!/usr/bin/env bash
# 05-ai-runtime.sh — Install AI runtime and model serving infrastructure:
# vLLM, Ollama, llama.cpp, and TensorRT (if NVIDIA).
# Run as root.

set -euo pipefail

echo "==> Installing AI runtime and model serving layer..."

# ── Docker (prerequisite) ───────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo "  Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

# ── Ollama — local LLM server ──────────────────────────────────
echo "  Installing Ollama..."
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi

# Enable and start Ollama as a service
systemctl enable ollama 2>/dev/null || true
systemctl start ollama 2>/dev/null || true

echo "  Ollama installed. Pull models with: ollama pull llama3"

# ── vLLM — high-throughput LLM serving ─────────────────────────
echo "  Setting up vLLM (Docker-based)..."
docker pull vllm/vllm-openai:latest 2>/dev/null || true

cat > /usr/local/bin/vllm-serve <<'EOF'
#!/usr/bin/env bash
# Usage: vllm-serve <model-name> [--port 8080]
MODEL="${1:?Usage: vllm-serve <model-name> [--port PORT]}"
shift
PORT=8080
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        *) shift ;;
    esac
done
exec docker run --rm --gpus all \
    -v ~/.cache/huggingface:/root/.cache/huggingface \
    -p "${PORT}:8000" \
    vllm/vllm-openai:latest \
    --model "${MODEL}" \
    --trust-remote-code
EOF
chmod +x /usr/local/bin/vllm-serve
echo "  vLLM ready. Serve models with: vllm-serve meta-llama/Llama-3-8B"

# ── llama.cpp — CPU/GPU inference for GGUF models ──────────────
echo "  Installing llama.cpp..."
LLAMACPP_DIR="/opt/llama.cpp"
if [ ! -d "${LLAMACPP_DIR}" ]; then
    apt-get install -y build-essential cmake git
    git clone https://github.com/ggerganov/llama.cpp.git "${LLAMACPP_DIR}"
    cd "${LLAMACPP_DIR}"

    if command -v nvidia-smi &>/dev/null; then
        cmake -B build -DGGML_CUDA=ON
    else
        cmake -B build
    fi
    cmake --build build --config Release -j "$(nproc)"

    ln -sf "${LLAMACPP_DIR}/build/bin/llama-server" /usr/local/bin/llama-server
    ln -sf "${LLAMACPP_DIR}/build/bin/llama-cli" /usr/local/bin/llama-cli
    cd /
fi
echo "  llama.cpp ready. Run with: llama-server -m /path/to/model.gguf"

# ── TensorRT (NVIDIA only) ─────────────────────────────────────
if command -v nvidia-smi &>/dev/null; then
    echo "  Installing TensorRT..."
    apt-get install -y tensorrt 2>/dev/null || {
        echo "  TensorRT not in apt repos. Install manually from NVIDIA."
    }
fi

# ── Python AI libraries ────────────────────────────────────────
echo "  Installing Python AI/ML base libraries..."
pip3 install --upgrade pip 2>/dev/null || true
pip3 install torch transformers accelerate safetensors huggingface-hub 2>/dev/null || true

echo "==> AI runtime layer installed."
echo ""
echo "Available model servers:"
echo "  ollama serve                           # Ollama (built-in)"
echo "  vllm-serve <model>                     # vLLM (Docker, GPU)"
echo "  llama-server -m <model.gguf>           # llama.cpp (CPU/GPU)"
