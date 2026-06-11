# Cassandra health check training

Hands-on curriculum for technical specialists: understand Cassandra / HCD cluster health from **live signals**, then deepen with **diagnostic collection**, **[sperf](https://github.com/datastax-labs/sperf)** CLI summaries, and **Montecristo** reports.

![cassandra-on-fire](/cassandra-on-fire.png)

```mermaid
flowchart LR
  A[1a/1b Snapshot] --> B[2 ds-collector]
  B --> S[2b sperf]
  B --> M[3 Montecristo]
  S --> M
  R[Ref: Key metrics] -.-> A
```

## Learning path

| Step | Guide | Focus |
|------|--------|--------|
| **1a** | [Health snapshot — VM / bare metal](docs/01-health-snapshot-bare-metal.md) | `nodetool`, logs, disk, OS — no extra tooling |
| **1b** | [Health snapshot — Kubernetes / Mission Control](docs/02-health-snapshot-kubernetes.md) | CRs, pods, MC UI, Mimir/Loki |
| **Ref** | [Key metrics to track](docs/05-key-metrics.md) | Triage flow, thresholds, nodetool/JMX, Mission Control panels |
| **2** | [Diagnostic collection](docs/03-diagnostic-collection.md) | [ds-collector](https://github.com/datastax/diagnostic-collection) bundles |
| **2b** | [sperf analysis](docs/06-sperf-analysis.md) | CLI summaries from collector tarballs (in Docker image) |
| **3** | [Montecristo analysis](docs/04-montecristo-analysis.md) | Containerized [Montecristo](https://github.com/datastax-labs/Montecristo) reports |

## Quick start — analysis container

Prerequisites: Docker, diagnostic `*.tar.gz` from ds-collector.

```bash
./scripts/analyze.sh build
./scripts/analyze.sh run my-ticket-id /path/to/collector-output
# Hugo: http://localhost:1313/final/
# sperf: ~/ds-discovery/my-ticket-id/sperf/

./scripts/analyze.sh sperf my-ticket-id /path/to/collector-output   # sperf only
```

See [docs/04-montecristo-analysis.md](docs/04-montecristo-analysis.md) and [docs/06-sperf-analysis.md](docs/06-sperf-analysis.md).

## Repository layout

| Path | Purpose |
|------|---------|
| [`docs/`](docs/01-health-snapshot-bare-metal.md) | Training modules + [key metrics](docs/05-key-metrics.md) + [sperf](docs/06-sperf-analysis.md) |
| [`docker/`](docker/Dockerfile) | Analysis image — Montecristo + sperf |
| [`scripts/analyze.sh`](scripts/analyze.sh) | Build and run helper |

## Lab environment

For a local Mission Control + HCD KinD lab, use [mc-lab](https://github.com/datastax/mc-lab) — especially [observability](https://github.com/datastax/mc-lab/blob/main/docs/05-observability.md) for metrics and logs during module **1b**.

## External tools

- [Diagnostic Collector](https://github.com/datastax/diagnostic-collection) — gather support bundles (SSH, Docker, or Kubernetes)
- [sperf](https://github.com/datastax-labs/sperf) — CLI performance analysis ([Docker image only](docs/06-sperf-analysis.md))
- [Montecristo](https://github.com/datastax-labs/Montecristo) — discovery analysis and Hugo report (built into this repo’s Docker image)
