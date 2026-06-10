# Cassandra health check training

Hands-on curriculum for technical specialists: understand Cassandra / HCD cluster health from **live signals**, then deepen with **diagnostic collection** and **Montecristo** analysis.

## Learning path

| Step | Guide | Focus |
|------|--------|--------|
| **1a** | [Health snapshot — VM / bare metal](docs/01-health-snapshot-bare-metal.md) | `nodetool`, logs, disk, OS — no extra tooling |
| **1b** | [Health snapshot — Kubernetes / Mission Control](docs/02-health-snapshot-kubernetes.md) | CRs, pods, MC UI, Mimir/Loki |
| **2** | [Diagnostic collection](docs/03-diagnostic-collection.md) | [ds-collector](https://github.com/datastax/diagnostic-collection) bundles |
| **3** | [Montecristo analysis](docs/04-montecristo-analysis.md) | Containerized [Montecristo](https://github.com/datastax-labs/Montecristo) reports |

## Quick start — Montecristo container

Prerequisites: Docker, diagnostic tarballs from ds-collector.

```bash
./scripts/analyze.sh build
./scripts/analyze.sh run my-ticket-id /path/to/collector-output
# Report: http://localhost:1313/final/
```

See [docs/04-montecristo-analysis.md](docs/04-montecristo-analysis.md) for encrypted artifacts, environment variables, and output layout.

## Repository layout

| Path | Purpose |
|------|---------|
| [`docs/`](docs/01-health-snapshot-bare-metal.md) | Training modules |
| [`docker/`](docker/Dockerfile) | Montecristo image (`Dockerfile`, `entrypoint.sh`) |
| [`scripts/analyze.sh`](scripts/analyze.sh) | Build and run helper |

## Lab environment

For a local Mission Control + HCD KinD lab, use [mc-lab](https://github.com/datastax/mc-lab) — especially [observability](https://github.com/datastax/mc-lab/blob/main/docs/05-observability.md) for metrics and logs during module **1b**.

## External tools

- [Diagnostic Collector](https://github.com/datastax/diagnostic-collection) — gather support bundles (SSH, Docker, or Kubernetes)
- [Montecristo](https://github.com/datastax-labs/Montecristo) — discovery analysis and Hugo report (built into this repo’s Docker image)
