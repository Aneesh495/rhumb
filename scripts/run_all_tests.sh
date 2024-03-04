#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "================================================================================"
echo "RHUMB ENGINE COMPLETE VERIFICATION SUITE"
echo "================================================================================"

echo "[1/4] Running V Unit and Integration Test Suites..."
v test src/core
v test src/graph
v test src/routing
v test src/matcher
v test src/tiles
v test src/formats
v test src/navigation
v test src/server
echo "[✓] All V test suites passed successfully!"
echo ""

echo "[2/4] Testing C ABI and Shared Library..."
(cd c_api && make test && make clean)
echo "[✓] C ABI verification passed successfully!"
echo ""

echo "[3/4] Running Python SDK Test Suite..."
(cd python && python3 -m unittest discover tests)
echo "[✓] Python SDK tests passed successfully!"
echo ""

echo "[4/4] Verifying Codebase Typography and Character Hygiene..."
python3 scripts/verify_no_dashes.py
echo "[✓] Typography verification passed successfully!"
echo ""

echo "================================================================================"
echo "ALL VERIFICATION PASSES COMPLETED WITH ZERO ERRORS!"
echo "================================================================================"
