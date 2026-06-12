# diagnostics

Local output directory for [ds-collector](https://github.com/datastax/diagnostic-collection) bundles (`*_artifacts_*.tar.gz`).

Configure the collector with `bastionBaseDir` pointing here — see [Diagnostic collection](../docs/04-diagnostic-collection.md).

```bash
mkdir -p diagnostics
ls ./diagnostics/*.tar.gz
./scripts/analyze.sh run my-ticket-id ./diagnostics
```

Generated artifacts in this folder are gitignored.
