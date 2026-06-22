#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"

chmod +x "$ROOT_DIR/.beads-hooks"/*
git config core.hooksPath .beads-hooks

echo "[hooks] Installed repo hooks from .beads-hooks."
echo "[hooks] Includes Beads integration plus gitleaks and Haxe formatter."
echo "[hooks] Refresh with: bd hooks install --shared --chain"
echo "[hooks] Install formatter with: haxelib install formatter"
