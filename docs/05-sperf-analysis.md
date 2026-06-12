# sperf — quick CLI analysis (Docker)

[sperf](https://github.com/datastax-labs/sperf) summarizes GC, StatusLogger, config diffs, and table hotspots from **ds-collector** bundles. It is **bundled in the analysis Docker image** — no local install required.

Use it after [diagnostic collection](04-diagnostic-collection.md), before or with [Montecristo](06-montecristo-analysis.md).

Official reference: [sperf user documentation](https://datastax-labs.github.io/sperf/).

---

## Input: collector tarballs

Point the container at the same directory as Montecristo: `*.tar.gz` from ds-collector (e.g. `./diagnostics/`).

sperf expects a legacy `nodes/<hostname>/` tree internally. The image **extracts tarballs and stages that layout automatically** — you do not extract or install sperf on your laptop.

---

## Run from the training image

```bash
./scripts/analyze.sh build   # once — installs sperf in the image

# sperf only (reads /artifacts/*.tar.gz inside the container)
# Use an ISSUE_ID instead of 'docker-lab' to track tickets: ./scripts/analyze.sh sperf ISSUE_ID ./diagnostics
./scripts/analyze.sh sperf docker-lab ./diagnostics
ls ./ds-discovery/docker-lab/sperf/
```

Skip sperf on a full run: `SKIP_SPERF=true ./scripts/analyze.sh run …`

---

## Output files

Under `./ds-discovery/<ISSUE_ID>/sperf/` (repo root, gitignored):

| File | Command |
|------|---------|
| `summary.txt` | `sperf` |
| `core-gc.txt` | `sperf core gc` |
| `core-statuslogger.txt` | `sperf core statuslogger` |
| `core-diag.txt` | `sperf core diag` |

---

## What sperf adds vs Montecristo

| | sperf | Montecristo |
|---|-------|-------------|
| **Speed** | Minutes | Longer |
| **Output** | Text files in `sperf/` | Hugo HTML report |
| **Strength** | GC timeline, statuslogger stages, config diff | Metrics DB, rules, infra checklist |

---

## Related

- [sperf on GitHub](https://github.com/datastax-labs/sperf)
- [Key metrics](07-key-metrics.md) — correlate GC, tpstats, tombstones
- [Montecristo analysis](06-montecristo-analysis.md)
