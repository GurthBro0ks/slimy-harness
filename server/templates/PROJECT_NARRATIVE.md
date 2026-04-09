# PROJECT_NARRATIVE.md — SlimyAI Server

> This file describes the WHY behind the system: why projects exist, how they relate,
> where the risk zones are, and what institutional knowledge is critical to preserve.

## Architecture Overview

### System Topology
- **NUC1** (this server): [TODO — what runs here]
- **NUC2**: [TODO — what runs there]
- **Connection**: Tailscale (nuc1-ts / nuc2-ts)

### Project Relationships
```
[TODO — describe how projects depend on each other]
```

### Data Flows
- [TODO — how does data flow between projects?]

## Risk Zones

### Services that are Dead and Should NOT be Restarted
- [TODO — fill from AGENTS.md "Intentionally Dead" section]

### Services that are Critical and Fragile
- [TODO — which services if killed would break the system?]

### Secrets / Forbidden Paths
- [TODO — list forbidden zones per project]

## Institutional Knowledge

### Known Failure Modes
- [TODO — document known past failures and their fixes]

### Critical Procedures
- [TODO — how to safely restart services, how to recover from common failures]

## Current State

> As of YYYY-MM-DD, verified by [agent/session]:

| Project | Path | Live? | Last Verified |
|---------|------|-------|---------------|
| (repo) | (path) | yes/no | YYYY-MM-DD |

## Project Map

| Project | Path | Language | What It Is |
|---------|------|----------|------------|
| (name) | (path) | (lang) | (description) |

---

*This file is sourced by Prompt P / C2 / PROJECT_NARRATIVE startup integration in Harness v3.*
*This is a placeholder — actual content to be added in a future session.*
