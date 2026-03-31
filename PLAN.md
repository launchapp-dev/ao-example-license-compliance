# License Compliance Scanner — Build Plan

## Overview

Dependency license compliance pipeline — scans a project's dependency tree with
`npx license-checker`, cross-references against a configurable license whitelist/blacklist,
flags copyleft, proprietary, and unknown licenses, generates a compliance matrix,
creates GitHub issues for violations requiring remediation, and produces an audit-ready
report. Designed for engineering and legal teams that need continuous license governance.

All scanning uses real CLI tools (`npx license-checker --json`, `npm ls --all --json`,
`gh issue create`). Agent phases handle classification, policy evaluation, and reporting.

---

## Agents (4)

| Agent | Model | Role |
|---|---|---|
| **scanner** | claude-haiku-4-5 | Fast — parses raw license-checker JSON output, normalizes into structured dependency records |
| **policy-checker** | claude-sonnet-4-6 | Evaluates each dependency against the license policy, classifies compliance status, uses sequential-thinking for edge cases |
| **reporter** | claude-sonnet-4-6 | Generates compliance matrix, violation summaries, and audit-ready markdown report |
| **issue-creator** | claude-haiku-4-5 | Drafts and creates GitHub issues for each violation requiring remediation |

### MCP Servers Used by Agents

- **filesystem** — all agents read/write JSON/markdown data files in `data/`
- **github** (gh-cli-mcp) — issue-creator uses for creating/labeling issues
- **sequential-thinking** — policy-checker uses for nuanced license classification (e.g., dual-licensed packages, license-with-exception)

---

## Workflows (2)

### 1. `compliance-scan` (primary — triggered per scan run)

Full pipeline: scan → normalize → policy check → report → issues.

**Phases:**

1. **scan-dependencies** (command)
   - Command: `npx license-checker --json --out data/scan-results/raw-licenses.json`
   - Also runs: `npm ls --all --json > data/scan-results/dep-tree.json`
   - Captures the full dependency tree with license metadata
   - Writes to `data/scan-results/`
   - Timeout: 120s

2. **normalize-licenses** (agent: scanner)
   - Reads `data/scan-results/raw-licenses.json` and `data/scan-results/dep-tree.json`
   - Normalizes each dependency into structured records:
     - `package_name`, `version`, `license_spdx`, `license_source` (package.json vs LICENSE file vs inferred)
     - `is_direct` (direct vs transitive), `depth` in tree
     - `repository_url`, `publisher`
   - Handles edge cases: multi-license (OR/AND), custom license text, missing license field
   - Writes `data/normalized/dependencies.json` — array of all dependency records
   - Writes `data/normalized/license-summary.json` — counts by license type

3. **evaluate-policy** (agent: policy-checker)
   - Reads `data/normalized/dependencies.json` and `config/license-policy.yaml`
   - Policy file defines:
     - `allowed`: list of approved SPDX identifiers (MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, etc.)
     - `copyleft_restricted`: licenses that need legal review (GPL-2.0, GPL-3.0, AGPL-3.0, LGPL-*, MPL-2.0)
     - `banned`: licenses explicitly prohibited (SSPL-1.0, BSL-1.1, BUSL-1.1, proprietary)
     - `exceptions`: specific packages exempt from policy (with reason and expiry date)
   - Uses sequential-thinking for ambiguous cases:
     - Dual-licensed packages (e.g., MIT OR GPL-3.0) — is the permissive option usable?
     - License-with-exception (e.g., GPL-2.0-with-classpath-exception)
     - Unknown/custom license text — attempt classification
   - Classifies each dependency:
     - `compliant` — license is in allowed list
     - `warning` — copyleft/restricted license, needs legal review
     - `violation` — banned license or no license detected
     - `unknown` — could not determine license, needs manual review
   - Decision contract:
     - `compliant` — all deps are compliant → proceed to report
     - `warning` — some warnings but no violations → proceed to report with advisory
     - `violation` — one or more violations found → proceed to report + issues
   - Writes `data/evaluation/compliance-results.json`
   - Writes `data/evaluation/violations.json` (filtered list of non-compliant deps)

4. **generate-report** (agent: reporter)
   - Reads all data from `data/evaluation/` and `data/normalized/`
   - Generates:
     - `reports/compliance-matrix.md` — full table: package | version | license | status | notes
     - `reports/executive-summary.md` — high-level stats: X deps scanned, Y compliant, Z warnings, W violations
     - `reports/violation-details.md` — per-violation: package, license, why it's flagged, recommended action (replace/get-exception/remove)
     - `reports/audit-package.md` — combined audit-ready document with all sections
   - Output includes:
     - Scan timestamp, project name, policy version
     - Dependency tree depth statistics
     - License distribution pie chart (as markdown table)
     - Remediation priority ranking (direct deps > transitive, banned > copyleft > unknown)

5. **create-issues** (agent: issue-creator)
   - Only runs if violations or warnings exist (reads `data/evaluation/violations.json`)
   - For each violation/warning, creates a GitHub issue:
     - Title: `[License] {package}@{version} — {license} ({status})`
     - Body: violation details, recommended action, links to package repo
     - Labels: `license-compliance`, `violation` or `warning`
   - Groups related violations (e.g., multiple packages with same license) into single issues when appropriate
   - Creates a tracking issue summarizing all findings with checklist
   - Writes `data/issues/created-issues.json` with issue URLs

### 2. `pre-release-gate` (release gate variant)

Streamlined pipeline for CI/CD integration — scan → evaluate → pass/fail decision.

**Phases:**

1. **scan-dependencies** (command) — same as above
2. **normalize-licenses** (agent: scanner) — same as above
3. **evaluate-policy** (agent: policy-checker) — same as above
4. **release-decision** (agent: policy-checker)
   - Reads compliance results
   - Decision contract:
     - `approve` — no violations, safe to release
     - `block` — violations found, cannot release until resolved
     - `exception` — violations exist but all have valid exceptions → approve with advisory
   - Writes `reports/release-gate-result.json` with pass/fail and details

---

## Supporting Files

### config/license-policy.yaml
Default license policy with common open-source licenses categorized:
- **allowed**: MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, CC0-1.0, Unlicense, 0BSD, BlueOak-1.0.0, CC-BY-3.0, CC-BY-4.0, Zlib, PSF-2.0, Python-2.0
- **copyleft_restricted**: GPL-2.0-only, GPL-2.0-or-later, GPL-3.0-only, GPL-3.0-or-later, AGPL-3.0-only, AGPL-3.0-or-later, LGPL-2.1-only, LGPL-3.0-only, MPL-2.0, EPL-1.0, EPL-2.0, CDDL-1.0, EUPL-1.2
- **banned**: SSPL-1.0, BSL-1.1, BUSL-1.1
- **exceptions**: empty by default (teams add their own)

### config/scan-config.yaml
Scan configuration:
- `target_path`: path to project to scan (default: current directory)
- `exclude_dev`: whether to skip devDependencies (default: false)
- `exclude_patterns`: glob patterns for packages to skip
- `depth_limit`: max transitive depth to scan (default: unlimited)

### data/ (generated at runtime)
```
data/
├── scan-results/
│   ├── raw-licenses.json      # Raw license-checker output
│   └── dep-tree.json          # npm ls output
├── normalized/
│   ├── dependencies.json      # Structured dependency records
│   └── license-summary.json   # Counts by license type
├── evaluation/
│   ├── compliance-results.json # Per-dep compliance status
│   └── violations.json         # Filtered violations/warnings
└── issues/
    └── created-issues.json     # Created GitHub issue URLs
```

### reports/ (generated at runtime)
```
reports/
├── compliance-matrix.md       # Full compliance table
├── executive-summary.md       # High-level stats
├── violation-details.md       # Per-violation details + remediation
├── audit-package.md           # Combined audit document
└── release-gate-result.json   # Pass/fail for CI gate
```

### scripts/scan-deps.sh
Shell script that runs the scan commands and handles error cases:
- Checks for package.json existence
- Runs `npx license-checker --json`
- Runs `npm ls --all --json` (tolerates exit code 1 from peer dep issues)
- Writes results to data/scan-results/
- Exit 0 always (scan failures are logged but don't crash the pipeline)

### sample-data/
Sample project with a mix of license types for demo/testing:
- `sample-data/package.json` — small project with MIT, Apache-2.0, GPL-3.0, and unlicensed deps
- `sample-data/node_modules/` — NOT included (generated via npm install at runtime)

---

## Schedules

| Schedule | Cron | Workflow | Purpose |
|---|---|---|---|
| `weekly-scan` | `0 9 * * 1` | compliance-scan | Monday 9am weekly compliance audit |
| `pre-release` | (manual trigger) | pre-release-gate | Run before each release to gate on compliance |

---

## Phase Routing

### compliance-scan workflow
```
scan-dependencies → normalize-licenses → evaluate-policy
                                              │
                              ┌────────────────┼────────────────┐
                              │                │                │
                          compliant         warning          violation
                              │                │                │
                              ▼                ▼                ▼
                       generate-report   generate-report   generate-report
                              │                │                │
                              ▼                ▼                ▼
                            (done)       create-issues     create-issues
                                              │                │
                                              ▼                ▼
                                           (done)           (done)
```

- `evaluate-policy` verdict `compliant` → skip create-issues, go to report only
- `evaluate-policy` verdict `warning` or `violation` → generate report then create issues
- On `evaluate-policy` returning `rework` (scan data incomplete) → re-run scan-dependencies

### pre-release-gate workflow
```
scan-dependencies → normalize-licenses → evaluate-policy → release-decision
                                                                  │
                                              ┌───────────────────┼──────────┐
                                              │                   │          │
                                           approve            exception    block
                                              │                   │          │
                                              ▼                   ▼          ▼
                                           (pass)             (pass*)     (fail)
```

---

## AO Features Demonstrated

- **Command phases** — real CLI tools: `npx license-checker`, `npm ls`, `gh issue create`
- **Multi-agent pipeline** — 4 agents with distinct roles and appropriate model sizes
- **Decision contracts** — compliance verdicts drive workflow routing
- **Output contracts** — structured JSON intermediates, markdown reports
- **Scheduled workflows** — weekly automated compliance scans
- **Phase routing** — rework loops on incomplete data, skip issue creation when compliant
- **Config-driven behavior** — license policy is external YAML, easily customizable
- **Dual workflows** — full audit pipeline + streamlined release gate
