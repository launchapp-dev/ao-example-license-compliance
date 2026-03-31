# License Compliance Scanner — Agent Context

## What This Repo Does

This is an AO workflow that scans Node.js project dependencies for license compliance.
It runs `npx license-checker` to extract license metadata, evaluates each dependency
against a configurable policy, generates audit-ready reports, and creates GitHub issues
for violations.

## Key Files to Know

| File | Purpose |
|---|---|
| `config/license-policy.yaml` | Defines allowed, copyleft_restricted, banned licenses, and package exceptions |
| `config/scan-config.yaml` | Target project path, exclude_dev flag, GitHub repo for issues |
| `scripts/scan-deps.sh` | Shell script that runs the actual scan commands |
| `data/scan-results/raw-licenses.json` | Raw output from `npx license-checker --json` |
| `data/normalized/dependencies.json` | Normalized dependency records (written by scanner agent) |
| `data/evaluation/violations.json` | Filtered list of violations/warnings (written by policy-checker) |
| `reports/` | All generated reports (written by reporter agent) |
| `data/issues/create-issues.sh` | Shell script to create GitHub issues (written by issue-creator) |

## Agent Responsibilities

- **scanner** (haiku): Parse raw JSON → normalized records. Handle alias normalization.
- **policy-checker** (sonnet): Evaluate policy. Issue `compliant/warning/violation/rework` verdict.
- **reporter** (sonnet): Write all markdown reports and `release-gate-result.json`.
- **issue-creator** (haiku): Write `create-issues.sh` and `created-issues.json`.

## Data Flow

```
scripts/scan-deps.sh
  → data/scan-results/raw-licenses.json
  → data/scan-results/dep-tree.json

scanner agent
  → data/normalized/dependencies.json
  → data/normalized/license-summary.json

policy-checker agent
  → data/evaluation/compliance-results.json
  → data/evaluation/violations.json
  (verdict: compliant / warning / violation / rework)

reporter agent
  → reports/compliance-matrix.md
  → reports/executive-summary.md
  → reports/violation-details.md
  → reports/audit-package.md
  → reports/release-gate-result.json

issue-creator agent
  → data/issues/create-issues.sh
  → data/issues/created-issues.json
```

## License Classification Logic

- **UNKNOWN** deps always trigger a `violation` verdict unless excepted in policy
- **Dual-licensed** packages (e.g., "MIT OR GPL-3.0"): if ANY option is allowed → compliant
- **Expired exceptions**: reclassify to base license status
- **GPL-2.0-with-classpath-exception**: treat as `warning`, not `violation`

## Workflows

- **compliance-scan**: Full pipeline with human review gate before GitHub issues are filed
- **pre-release-gate**: Fast variant for CI/CD — returns approve/block/exception verdict

## SPDX References

When classifying licenses, use the SPDX identifier format:
https://spdx.org/licenses/

Common aliases to normalize:
- "Apache 2.0" → "Apache-2.0"
- "BSD" → "BSD-2-Clause"
- "MIT*" → "MIT"
- "(none)", "UNLICENSED", "" → "UNKNOWN"
