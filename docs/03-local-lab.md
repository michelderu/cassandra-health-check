# Local lab — Cassandra container and stress

Single-node **`cassandra:5.0`** on your laptop for practicing [diagnostic collection](04-diagnostic-collection.md).

---

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| **Docker** | Docker Engine with `docker compose` |
| **Ports** | `9042` free on the host (CQL) |

Compose file: [`docker/docker-compose.cassandra.yml`](../docker/docker-compose.cassandra.yml).

| Setting | Value |
|---------|--------|
| Image | `cassandra:5.0` |
| Container | `ds-collector-test-cassandra` |
| Cluster | `ds-collector-test` |
| DC / rack | `dc1` / `rack1` |
| Heap | 512M / 128M young |

---

## 1) Start Cassandra

From this repository:

```bash
docker compose -f docker/docker-compose.cassandra.yml up -d
docker compose -f docker/docker-compose.cassandra.yml ps
```

First boot can take 1–2 minutes. Wait until the service is **healthy** or `nodetool status` shows one **UN** node:

```bash
docker exec ds-collector-test-cassandra nodetool status
```

Tail logs if needed:

```bash
docker compose -f docker/docker-compose.cassandra.yml logs -f cassandra
```

---

## 2) Generate load (optional)

A fresh container has almost no CQL traffic — `tablestats`, `cfstats`, and [sperf](05-sperf-analysis.md) often show **N/A** until you generate load. `nodetool` reports stats but does not insert rows; use **`cassandra-stress`** (included in the image) via the helper script:

```bash
./scripts/lab-stress.sh
```

Default: 100k writes + 100k reads into keyspace `lab_stress` (table `standard1`), then nodetool verification.

| Command | Purpose |
|---------|---------|
| `./scripts/lab-stress.sh` | Write + read + verify (`tablestats`, `tpstats`, `compactionstats`) |
| `./scripts/lab-stress.sh write` | Writes only |
| `./scripts/lab-stress.sh read` | Reads only (after write) |
| `./scripts/lab-stress.sh verify` | Nodetool stats without loading data |

Customize load:

```bash
LAB_ROWS=200000 LAB_THREADS=8 ./scripts/lab-stress.sh write
LAB_READS=50000 ./scripts/lab-stress.sh read
./scripts/lab-stress.sh verify
```

| Variable | Default | Meaning |
|----------|---------|---------|
| `LAB_CONTAINER` | `ds-collector-test-cassandra` | Target container |
| `LAB_KEYSPACE` | `lab_stress` | Stress keyspace |
| `LAB_ROWS` | `100000` | Write row count |
| `LAB_READS` | `100000` | Read operation count |
| `LAB_THREADS` | `4` | Stress thread count |

---

## 3) Next steps

1. [Diagnostic collection — Docker lab](04-diagnostic-collection.md#local-lab--test-cassandra-container) — run `ds-collector` against `ds-collector-test-cassandra`.
2. [sperf](05-sperf-analysis.md) and [Montecristo](06-montecristo-analysis.md) on the resulting tarballs.

---

## Tear down

```bash
docker compose -f docker/docker-compose.cassandra.yml down
```
