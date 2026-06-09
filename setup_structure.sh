#!/usr/bin/env bash
# =============================================================================
# setup_structure.sh — openAIOS Project Directory Generator
# =============================================================================
# Usage:
#   ./setup_structure.sh              # Creates ./openAIOS/ in current directory
#   ./setup_structure.sh /path/to/dir # Creates structure inside a custom path
#   ./setup_structure.sh --in-place   # Creates structure in the current directory
#                                       (useful when you've already cloned the repo)
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"
BOLD="\033[1m"

# ── Parse args ────────────────────────────────────────────────────────────────
IN_PLACE=false
ROOT=""

if [[ "${1:-}" == "--in-place" ]]; then
  IN_PLACE=true
  ROOT="$(pwd)"
elif [[ -n "${1:-}" ]]; then
  ROOT="$1"
else
  ROOT="$(pwd)/openAIOS"
fi

# ── Safety check ──────────────────────────────────────────────────────────────
if [[ "$IN_PLACE" == false && -d "$ROOT" ]]; then
  echo -e "${YELLOW}⚠️  Directory already exists: $ROOT${RESET}"
  read -r -p "   Continue and create missing directories? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

echo ""
echo -e "${BOLD}${CYAN}openAIOS — Project Structure Generator${RESET}"
echo -e "${CYAN}───────────────────────────────────────${RESET}"
echo -e "  Target: ${BOLD}$ROOT${RESET}"
echo ""

# ── Helper: make dir + .gitkeep ───────────────────────────────────────────────
make_dir() {
  local dir="$ROOT/$1"
  mkdir -p "$dir"
  # Add .gitkeep so empty dirs are tracked by git
  if [[ ! -f "$dir/.gitkeep" ]]; then
    touch "$dir/.gitkeep"
  fi
  echo -e "  ${GREEN}✔${RESET}  $1/"
}

# ── Helper: create file if it doesn't exist ───────────────────────────────────
make_file() {
  local file="$ROOT/$1"
  local content="${2:-}"
  if [[ ! -f "$file" ]]; then
    echo "$content" > "$file"
    echo -e "  ${GREEN}✔${RESET}  $1"
  else
    echo -e "  ${YELLOW}–${RESET}  $1 ${YELLOW}(already exists, skipped)${RESET}"
  fi
}

# =============================================================================
# DIRECTORIES
# =============================================================================
echo -e "${BOLD}Creating directories...${RESET}"

# core/ — OS Kernel Integration & System Services
make_dir "core/kernel"
make_dir "core/memory"
make_dir "core/scheduler"

# shell/ — AI Shell / Command Interface
make_dir "shell/interpreter"
make_dir "shell/executor"
make_dir "shell/history"

# wm/ — AI Window Manager / GUI
make_dir "wm/compositor"
make_dir "wm/layouts"
make_dir "wm/widgets"

# plugins/ — Plugin & App Ecosystem
make_dir "plugins/sdk"
make_dir "plugins/loader"
make_dir "plugins/examples"

# ai/ — Shared AI Layer
make_dir "ai/models"
make_dir "ai/context"
make_dir "ai/providers"

# config/
make_dir "config"

# docs/
make_dir "docs"

# tests/
make_dir "tests/unit"
make_dir "tests/integration"
make_dir "tests/e2e"

# scripts/
make_dir "scripts"

# .github/
make_dir ".github/workflows"
make_dir ".github/ISSUE_TEMPLATE"

echo ""

# =============================================================================
# STUB FILES
# =============================================================================
echo -e "${BOLD}Creating stub files...${RESET}"

# .github templates
make_file ".github/PULL_REQUEST_TEMPLATE.md" "## Description

<!-- What does this PR do? -->

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactor

## Checklist
- [ ] Tests added / updated
- [ ] Documentation updated
- [ ] Linter passes
"

make_file ".github/ISSUE_TEMPLATE/bug_report.md" "---
name: Bug Report
about: Report a bug in openAIOS
labels: bug
---

**Describe the bug**

**Steps to reproduce**

**Expected behavior**

**Environment**
- OS:
- Version:
"

make_file ".github/ISSUE_TEMPLATE/feature_request.md" "---
name: Feature Request
about: Suggest a new feature for openAIOS
labels: enhancement
---

**Problem / motivation**

**Proposed solution**

**Alternatives considered**
"

# docs stubs
make_file "docs/architecture.md" "# Architecture

> High-level system design for openAIOS.

## Components

- **core/** — OS kernel integration and system services
- **shell/** — AI shell and command interface
- **wm/** — AI window manager and GUI
- **plugins/** — Plugin and app ecosystem
- **ai/** — Shared AI inference layer
"

make_file "docs/getting-started.md" "# Getting Started

## Prerequisites

- Node.js ≥ 18, Python ≥ 3.11, or Rust (per component)
- An LLM provider API key (OpenAI, Anthropic, or Ollama)

## Setup

\`\`\`bash
git clone https://github.com/YOUR_USERNAME/openAIOS.git
cd openAIOS
./scripts/setup.sh
\`\`\`
"

make_file "docs/plugin-api.md" "# Plugin API Reference

> Documentation for building plugins on the openAIOS platform.

## SDK Overview

See \`plugins/sdk/\` for the full SDK source.
"

# CONTRIBUTING
make_file "CONTRIBUTING.md" "# Contributing to openAIOS

Thank you for your interest in contributing!

## How to Contribute

1. Fork the repo and create a branch: \`git checkout -b feature/your-feature\`
2. Make your changes and add tests
3. Open a pull request against \`main\`

## Code Style

- Follow existing conventions per component
- Keep commits focused and well-described

## Reporting Bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md).
"

# LICENSE
make_file "LICENSE" "MIT License

Copyright (c) $(date +%Y) openAIOS Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the \"Software\"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"

# .gitignore
make_file ".gitignore" "# Dependencies
node_modules/
__pycache__/
*.pyc
target/

# Environment
.env
.env.local
*.env

# Build outputs
dist/
build/
*.o
*.so
*.dylib

# IDE
.vscode/
.idea/
*.swp

# OS
.DS_Store
Thumbs.db

# Logs
*.log
logs/
"

echo ""

# =============================================================================
# SUMMARY
# =============================================================================
echo -e "${CYAN}───────────────────────────────────────${RESET}"
echo -e "${BOLD}${GREEN}✅  Done!${RESET} Structure created at:"
echo -e "   ${BOLD}$ROOT${RESET}"
echo ""

# Print tree if 'tree' is available
if command -v tree &>/dev/null; then
  echo -e "${BOLD}Directory tree:${RESET}"
  tree -a --dirsfirst -I '.git' "$ROOT"
else
  echo -e "${YELLOW}Tip:${RESET} Install 'tree' to visualize the full structure."
  echo -e "     macOS: brew install tree  |  Ubuntu: apt install tree"
fi

echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo -e "  1. cd into your project:   ${CYAN}cd $ROOT${RESET}"
echo -e "  2. Init git (if needed):   ${CYAN}git init && git add . && git commit -m 'chore: scaffold project structure'${RESET}"
echo -e "  3. Push to GitHub:         ${CYAN}git remote add origin <your-repo-url> && git push -u origin main${RESET}"
echo ""
