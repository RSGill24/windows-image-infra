#!/usr/bin/env bash
set -euo pipefail

# Shutdown guard for dormant-friendly patching windows.
# If the VM is started only for patching, schedule a shutdown to control cost.
sudo shutdown -h +120 || true
