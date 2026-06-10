# OpenAIOS
AI-Native Operating Platform for Applications and Agents

Why AI Needs a New Operating Platform?

  Linux manages processes. VMware manages VMs. Kubernetes manages containers. Open AI OS manages AI.


$$OpenAIOS = \text{Kernel} + \text{User Space Utilities} + \text{AI Runtime Stack} + \text{Model Serving} + \text{AI Platform Services} + \text{AI Apps (Reference/CLI)}$$

---
#  System Architecture

## High-Level Architecture Diagram

The architecture is strictly organized into discrete horizontal layers, each providing well-defined backend services to the layer above it. The platform acts as an API-first operating environment, terminating at the application framework daemon level.

```
+-----------------------------------------------------------------------+
| 5. AI APPLICATIONS / REFERENCE IMPLEMENTATIONS                         |
|    VaaniAI Daemon (vaaniaid) · System CLI · SDK Native Agents         |
+-----------------------------------------------------------------------+
| 4. AI PLATFORM SERVICES (The "OS Intelligence" Layer)                |
|    Agent Runtime  ·  Workflow Engine  ·  API Gateway  ·  Security Svc |
+-----------------------------------------------------------------------+
| 3. MODEL SERVING LAYER                                                |
|    vLLM  ·  Ollama  ·  Triton Inference Server  ·  llama.cpp          |
+-----------------------------------------------------------------------+
| 2. AI RUNTIME STACK                                                   |
|    CUDA / ROCm  ·  Container Runtime (containerd)  ·  GPU Scheduler   |
+-----------------------------------------------------------------------+
| 1. OPENAIOS HARDWARE ABSTRACTION LAYER (Debian Kernel + User Space)   |
|    GPU Kernel  ·  XFS + io_uring  ·  NUMA/HugePages  ·  CPU Isolation  |
+-----------------------------------------------------------------------+
| BASE HARDWARE                                                         |
|    CPUs (x86_64)  ·  GPUs (NVIDIA/AMD)  ·  NVMe Storage  ·  Networking|
+-----------------------------------------------------------------------+

```

## Layer Descriptions

### Layer 1 — OpenAIOS Hardware Abstraction Layer (Debian Kernel + User Space)

A minimal, hardened, Debian-derived Linux kernel and foundational system utilities (`systemd`, toolchains, core shell utilities) stripped of desktop environments, audio servers, and legacy drivers.

* **GPU-First Scheduler:** Tailored directly for synchronous CUDA/ROCm execution paths and massive parallel tensor calculations.
* **Memory & CPU Tuning:** Enforces NUMA-aware memory allocations, strict CPU isolation (via `isolcpus`), and transparent huge pages to eliminate memory paging latencies during inference.
* **High-Throughput Storage Subsystem:** Utilizes the XFS filesystem paired natively with `io_uring` and GPU Direct Storage (GDS) to stream model weights directly from NVMe storage into VRAM, bypassing CPU memory bus bottlenecks.

### Layer 2 — AI Runtime Stack

The hardware acceleration and isolation layer that translates containerized instructions into compute execution.

* **Compute Runtimes:** Native integration of NVIDIA CUDA/TensorRT and AMD ROCm pipelines directly at the system layer.
* **Low-Overhead Containerization:** Utilizes a highly optimized, rootless `containerd` engine as the default platform runtime to manage service lifecycles without the performance tax of heavy hypervisors.
* **GPU Resource Broker:** Tracks and partitions raw hardware capabilities, providing sandboxed containers with structured pathways to compute matrices.

### Layer 3 — Model Serving Layer

An abstracted orchestration layer managing concurrent multi-model inference backends optimized for specific hardware footprints.

* **vLLM Engine:** Default engine for high-concurrency production LLMs, relying on PagedAttention to minimize VRAM fragmentation.
* **Ollama Engine:** Handles developer-focused local model iterations, packaging, and fast iterative testing.
* **llama.cpp Engine:** Leveraged for low-resource quantization architectures, maximizing performance on edge hardware or standard general CPUs.
* **Triton Inference Server:** Provides dynamic batching capabilities for complex, multi-model execution graphs and concurrent multi-framework architectures.

### Layer 4 — AI Platform Services

The functional intelligence boundary of OpenAIOS, replacing traditional operating system abstractions (like process IPC or file system permissions) with AI-native primitives.

* **Agent Runtime & Workflow Engine:** Manages state persistence, execution boundaries, and asynchronous tool-calling loops for autonomous actors.
* **API Gateway:** A high-performance gRPC and REST routing bus that multiplexes incoming execution requests from decoupled external consumers (external Web, Desktop, Mobile, or Voice client interfaces).
* **AI Security & Audit Engines:** Enforces declarative system-level permission manifests on agents, intercepts prompts for runtime injection filtering, and records immutable validation traces to a local audit trail.

### Layer 5 — AI Applications / Reference Implementations

The execution ceiling of the operating platform. Rather than hosting visual application wrappers, this layer hosts the underlying background daemons and infrastructure scripts.

* **VaaniAI Daemon (`vaaniaid`):** The flagship workspace application implemented as a headless, network-accessible daemon. It handles core workflow logic, RAG ingestion pipelines, and semantic processing, exposing secure API hooks for external frontends.
* **System CLI Utilities:** Core administrative shells used by system operators to install dependencies, monitor token throughput, register new fine-tuned models, and query system health.


# Open AI OS Base Image Build

## Platform Decision

Open AI OS is built on **Debian Minimal** and enhanced with:

- Immutable OS design
- A/B root partition model
- Atomic image-based updates
- Container-first runtime
- Dedicated AI model and data partitions

Final positioning:

```text
Open AI OS = Debian Minimal + Flatcar-style reliability + AI-native control plane
```

## High-Level Stack

```text
AI Applications
  VaaniAI | AI Agents | Voice Apps | RAG Apps

Open AI OS Core
  GPU Manager | AI Scheduler | Model Lifecycle
  AI Security | AI Storage | Observability

Container Runtime
  containerd / Docker / Podman

Debian Minimal Immutable Base OS
  Read-only root + controlled writable areas

Linux Kernel + Drivers

Hardware
  CPU | GPU | Storage | Network
```

## Disk Layout

```text
/dev/nvme0n1p1  /boot/efi
/dev/nvme0n1p2  RootA
/dev/nvme0n1p3  RootB
/dev/nvme0n1p4  Recovery
/dev/nvme0n1p5  /models
/dev/nvme0n1p6  /var/log
/dev/nvme0n1p7  /data
```

## Atomic Update Flow

```text
Boot RootA
  ↓
Download signed Open AI OS image
  ↓
Verify signature and checksum
  ↓
Write new image to RootB
  ↓
Update bootloader
  ↓
Reboot RootB
  ↓
Health check
  ↓
Mark RootB active or rollback to RootA
```

## Build Example

```bash
sudo ./build-openaios-image.sh --apply \
  --image=/tmp/openaios-amd64.img \
  --size=120G \
  --release=bookworm \
  --profile=appliance
```

## Profiles

- `appliance`: minimal AI appliance runtime.
- `developer`: adds debug and build tools.
- `enterprise`: adds operations and monitoring packages.

## Runtime Model

The following should run as containers:

- VaaniAI
- Whisper STT
- Translation service
- LLM service
- TTS service
- Vector database
- RAG pipeline
- Monitoring stack
- Web dashboard

Host OS keeps only:

- systemd
- containerd / podman
- nftables
- OpenSSH
- GPU drivers
- Open AI OS services
