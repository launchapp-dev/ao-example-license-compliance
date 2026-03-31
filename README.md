# License Compliance Scanner

Automated dependency license scanning — runs `npx license-checker`, evaluates licenses against your policy, generates audit-ready reports, and files GitHub issues for violations requiring remediation.

---

## Workflow Diagram

```
┌─────────────────┐
│  compliance-scan│  (or triggered by weekly-scan schedule)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│scan-dependencies│  npx license-checker --json
│   (command)     │  npm ls --all --json
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│normalize-licenses│  Parse + normalize SPDX IDs
│   (scanner)     │  Resolve aliases, mark unknowns
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────────────┐
│              evaluate-policy                     │
│            (policy-checker)                      │
│  Checks each dep against config/license-policy  │
│  Uses sequential-thinking for edge cases         │
└───────┬─────────────────┬───────────────┬───────┘
        │                 │               │
    compliant           warning        violation
        │                 │               │
        ▼                 ▼               ▼
┌─────────────────────────────────────────────────┐
│              generate-report                     │
│               (reporter)                         │
│  compliance-matrix.md, executive-summary.md      │
│  violation-details.md, audit-package.md          │
└────────────────────────┬────────────────────────┘
                         │
                         ▼
               ┌─────────────────┐
               │review-before-   │  Manual gate
               │   filing        │  Human approves before
               └────────┬────────┘  issues are filed
                        │
                        ▼
               ┌─────────────────┐
               │  create-issues  │  gh issue create per violation
               │ (issue-creator) │  Groups by license type
               └─────────────────┘

── Pre-release Gate (separate workflow) ──────────────────────

scan → normalize → evaluate → release-decision
                                    │
                    ┌───────────────┼──────────────┐
                    │               │              │
                  approve       exception        block
                  (pass)        (pass*)          (fail)
```

---

## Quick Start

```bash
# Point to the project you want to scan
# Edit config/scan-config.yaml → target_path: "/path/to/your/project"

cd examples/license-compliance
ao daemon start

# Run a full compliance scan
ao queue enqueue \
  --title "compliance-scan-$(date +%Y-%m-%d)" \
  --description "Weekly license audit" \
  --workflow-ref compliance-scan

# Or run the pre-release gate
ao queue enqueue \
  --title "pre-release-gate-v2.1.0" \
  --description "License gate for v2.1.0 release" \
  --workflow-ref pre-release-gate

# Watch progress
ao daemon stream --pretty

# Check results
cat reports/executive-summary.md
cat reports/violation-details.md
```

### Scan a specific project

Edit `config/scan-config.yaml`:

```yaml
target_path: "/path/to/your/node/project"
exclude_dev: true   # production deps only
github_repo: "myorg/myproject"  # for issue creation
```

### Use sample data for testing

```bash
# Copy sample project to a temp location and scan it
cp -r sample-data /tmp/sample-compliance-test
cd /tmp/sample-compliance-test && npm install
# Then set target_path: "/tmp/sample-compliance-test" in config/scan-config.yaml
```

---

## Agents

| Agent | Model | Role |
|---|---|---|
| **scanner** | claude-haiku-4-5 | Fast parser — reads raw `license-checker` output, normalizes SPDX IDs and license aliases, resolves direct vs transitive deps |
| **policy-checker** | claude-sonnet-4-6 | Evaluates each dep against `config/license-policy.yaml`, handles edge cases (dual-license, exceptions, GPL variants) using sequential-thinking |
| **reporter** | claude-sonnet-4-6 | Generates compliance matrix, executive summary, violation details, and combined audit package in markdown |
| **issue-creator** | claude-haiku-4-5 | Creates GitHub issues for violations — groups by license type, creates master tracking issue with checklist |

---

## AO Features Demonstrated

| Feature | Where |
|---|---|
| **Command phases** | `scan-dependencies` — real CLI: `npx license-checker`, `npm ls`, shell script |
| **Multi-agent pipeline** | 4 agents with distinct roles and model sizes (haiku for speed, sonnet for reasoning) |
| **Decision contracts** | `evaluate-policy` returns `compliant/warning/violation/rework` to drive routing |
| **Phase routing (rework loop)** | `evaluate-policy` `rework` verdict → re-runs `scan-dependencies` (max 2 retries) |
| **Manual gate** | `review-before-filing` — human approves before GitHub issues are created |
| **Scheduled workflows** | `weekly-scan` — cron `0 9 * * 1` (Monday 9am) |
| **Dual workflows** | `compliance-scan` (full audit) + `pre-release-gate` (CI/CD streamlined) |
| **Config-driven behavior** | License policy is external YAML — no code changes needed to customize |
| **Output contracts** | Structured JSON intermediates between phases, markdown reports as outputs |
| **Sequential-thinking MCP** | Policy checker uses it for nuanced license edge cases |

---

## Requirements

### Tools
- Node.js 18+ with `npm`
- `npx` (included with npm)
- `gh` CLI (for GitHub issue creation) — run `gh auth login` first

### API Keys / Auth
| Service | Variable | Required For |
|---|---|---|
| GitHub | `GH_TOKEN` | Creating issues via `gh-cli-mcp` |

### MCP Servers (auto-installed via npx)
- `@modelcontextprotocol/server-filesystem` — file read/write
- `@modelcontextprotocol/server-sequential-thinking` — structured reasoning for edge cases
- `gh-cli-mcp` — GitHub issue creation

---

## Output Files

```
reports/
├── compliance-matrix.md      # Full dep × license table
├── executive-summary.md      # Stats + risk rating
├── violation-details.md      # Per-violation remediation guide
├── audit-package.md          # Combined audit document (submit to legal)
└── release-gate-result.json  # Pass/fail for CI integration

data/
├── scan-results/
│   ├── raw-licenses.json     # Raw license-checker output
│   ├── dep-tree.json         # npm ls output
│   └── scan-meta.json        # Scan metadata (timestamp, count)
├── normalized/
│   ├── dependencies.json     # Structured dep records
│   └── license-summary.json  # License type counts
├── evaluation/
│   ├── compliance-results.json  # Per-dep compliance status
│   └── violations.json          # Filtered violations/warnings
└── issues/
    ├── create-issues.sh      # Shell script to create GitHub issues
    └── created-issues.json   # Issue tracker
```

---

## Customizing the Policy

Edit `config/license-policy.yaml` to:
- **Add allowed licenses** — add SPDX ID to `allowed` list
- **Add package exceptions** — add to `exceptions` with reason + expiry
- **Change copyleft treatment** — move licenses between `copyleft_restricted` and `banned`

```yaml
exceptions:
  "some-gpl-package@1.2.3":
    reason: "Used only in test environment, not distributed"
    approver: "legal@example.com"
    approved_at: "2026-01-15"
    expires: "2026-12-31"
```
