#!/usr/bin/env bash
# scan-deps.sh — Run license-checker and npm ls, write results to data/scan-results/
# Called by the scan-dependencies command phase.
# Exit 0 always — scan failures are logged but do not crash the pipeline.

set -euo pipefail

SCAN_DIR="data/scan-results"
mkdir -p "$SCAN_DIR"

# Read target path from config (default: current directory)
TARGET_PATH=$(python3 -c "
import sys
try:
    import yaml
    with open('config/scan-config.yaml') as f:
        cfg = yaml.safe_load(f)
    print(cfg.get('target_path', '.'))
except Exception:
    print('.')
" 2>/dev/null || echo ".")

EXCLUDE_DEV=$(python3 -c "
import sys
try:
    import yaml
    with open('config/scan-config.yaml') as f:
        cfg = yaml.safe_load(f)
    print('true' if cfg.get('exclude_dev', False) else 'false')
except Exception:
    print('false')
" 2>/dev/null || echo "false")

echo "=== License Compliance Scan ==="
echo "Target: $TARGET_PATH"
echo "Exclude dev deps: $EXCLUDE_DEV"
echo "Output: $SCAN_DIR/"
echo ""

# Check for package.json
if [ ! -f "$TARGET_PATH/package.json" ]; then
    echo "ERROR: No package.json found at $TARGET_PATH"
    echo "Please set target_path in config/scan-config.yaml to a Node.js project directory."
    # Write empty results so downstream phases can handle gracefully
    echo '{}' > "$SCAN_DIR/raw-licenses.json"
    echo '{}' > "$SCAN_DIR/dep-tree.json"
    exit 0
fi

# Install dependencies if node_modules doesn't exist
if [ ! -d "$TARGET_PATH/node_modules" ]; then
    echo "Installing dependencies in $TARGET_PATH..."
    (cd "$TARGET_PATH" && npm install --prefer-offline --no-audit 2>&1) || true
fi

# Build license-checker flags
CHECKER_FLAGS="--json"
if [ "$EXCLUDE_DEV" = "true" ]; then
    CHECKER_FLAGS="$CHECKER_FLAGS --excludePackages dev"
fi

# Run license-checker
echo "Running npx license-checker..."
(cd "$TARGET_PATH" && npx --yes license-checker $CHECKER_FLAGS) \
    > "$SCAN_DIR/raw-licenses.json" 2>/dev/null \
    || {
        echo "WARN: license-checker failed or returned no results"
        echo '{}' > "$SCAN_DIR/raw-licenses.json"
    }

PACKAGE_COUNT=$(python3 -c "
import json, sys
try:
    with open('$SCAN_DIR/raw-licenses.json') as f:
        data = json.load(f)
    print(len(data))
except:
    print(0)
")
echo "Found $PACKAGE_COUNT packages with license data"

# Run npm ls for dependency tree (ignore exit code 1 from peer dep warnings)
echo "Running npm ls for dependency tree..."
(cd "$TARGET_PATH" && npm ls --all --json 2>/dev/null) \
    > "$SCAN_DIR/dep-tree.json" \
    || true

# Validate dep-tree.json is valid JSON
python3 -c "
import json, sys
try:
    with open('$SCAN_DIR/dep-tree.json') as f:
        json.load(f)
    print('dep-tree.json: valid JSON')
except Exception as e:
    print(f'WARN: dep-tree.json invalid ({e}), writing empty object')
    with open('$SCAN_DIR/dep-tree.json', 'w') as f:
        f.write('{}')
"

# Write scan metadata
python3 -c "
import json, datetime
meta = {
    'scan_timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
    'target_path': '$TARGET_PATH',
    'exclude_dev': '$EXCLUDE_DEV' == 'true',
    'package_count': $PACKAGE_COUNT
}
with open('$SCAN_DIR/scan-meta.json', 'w') as f:
    json.dump(meta, f, indent=2)
print('Scan metadata written to $SCAN_DIR/scan-meta.json')
"

echo ""
echo "=== Scan complete ==="
echo "Results written to $SCAN_DIR/"
