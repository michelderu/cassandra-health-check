# ds-discovery

Local output from `./scripts/analyze.sh` — Montecristo reports and [sperf](../docs/05-sperf-analysis.md) summaries.

Default layout:

```
ds-discovery/<ISSUE_ID>/
├── extracted/
├── metrics.db
├── reports/montecristo/    # Hugo site → http://localhost:1313/final/
└── sperf/                  # summary.txt, core-*.txt
```

See [Montecristo analysis](../docs/06-montecristo-analysis.md). Generated content in this folder is gitignored.
