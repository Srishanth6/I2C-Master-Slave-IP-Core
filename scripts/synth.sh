#!/usr/bin/env bash
# Runs Yosys synthesis on Linux (yosys on PATH).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p synth
yosys -q -l synth/ci_synth_full.log -s scripts/synth.ys
echo "synthesis OK"
