#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
# Import first so global classes are registered on a fresh checkout.
# Godot can return zero despite script errors: explicitly check its diagnostics too.
log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT
run_check() {
  "$GODOT_BIN" "$@" 2>&1 | tee "$log_file"
  if grep -Eq 'SCRIPT ERROR:|ERROR:' "$log_file"; then
    exit 1
  fi
}
run_check --headless --editor --path . --quit
run_check --headless --path . --script tests/validate_facility.gd
run_check --headless --path . --script tests/validate_mobility.gd
run_check --headless --path . --script tests/validate_manipulation_followup.gd
run_check --headless --path . --script tests/validate_equipment_poses.gd
run_check --headless --path . --script tests/validate_project_configuration.gd
run_check --headless --path . --script tests/validate_environment.gd
run_check --headless --path . --script tests/validate_precision_placement.gd
run_check --headless --path . --script tests/validate_terminal.gd
run_check --headless --path . --quit-after 120
