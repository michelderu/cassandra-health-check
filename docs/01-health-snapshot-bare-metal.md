# Health snapshot — VM and bare metal

Before opening support bundles or analysis tools, learn to answer one question in under five minutes: **is the cluster healthy right now, and where is the pain?**

This module uses only what is already on the node or reachable over SSH — no diagnostic collector, no Montecristo, no Mission Control.

## What you are assessing

| Layer | Question |
|-------|----------|
| **Cluster membership** | Are all nodes up and in the right state (UN/DN)? |
| **Data distribution** | Is the token ring balanced? Any hotspots? |
| **Workload** | Pending compactions, thread-pool backlogs, timeouts? |
| **Storage** | Disk space on data and commitlog volumes? |
| **Runtime** | Is the Cassandra/HCD process running, GC pausing, OOM risk? |
| **OS** | CPU load, memory pressure, swap, NTP drift? |

Work top-down: cluster → node → disk → logs.

---

## 1) Cluster membership — `nodetool status`

Pick any live node and run:

```bash
nodetool status
```

| State | Meaning | Action |
|-------|---------|--------|
| **UN** | Up, Normal | Healthy member |
| **UJ** | Up, Joining | Bootstrap in progress — expect until complete |
| **UL** | Up, Leaving | Decommission in progress |
| **DN** | Down, Normal | Node unreachable — investigate immediately |
| **DJ** | Down, Joining | Failed or stuck join |

Also note:

- **Load** per node — large skew may indicate uneven partitioning or a hot node.
- **Owns** — should align with replication factor and token count per DC.
- **Rack/DC** columns — confirm topology matches design.

Quick ring view for a keyspace:

```bash
nodetool describering <keyspace>
```

---

## 2) Thread pools and compaction — backpressure signals

```bash
nodetool tpstats
nodetool compactionstats
```

**tpstats** — look for pools with high **Pending** or **Blocked**:

- `Native-Transport-Requests` — client read/write pressure.
- `ReadStage` / `MutationStage` — coordinator and replica work.
- `CompactionExecutor` — compactions falling behind.

**compactionstats** — many pending tasks or a single huge task can explain latency spikes.

Optional drill-down:

```bash
nodetool tablestats <keyspace>.<table>
nodetool getcompactionthroughput
```

---

## 3) Schema and gossip — consistency of metadata

```bash
nodetool describecluster
nodetool gossipinfo | head -40
```

- One cluster name, one partitioner, consistent release across nodes.
- Gossip shows **generation / version** per endpoint — stale versions on a node can mean it has been partitioned.

---

## 4) Storage and OS — the silent killers

On each node (or via your config management):

```bash
df -h
du -sh /var/lib/cassandra/data/* 2>/dev/null | sort -h | tail
iostat -xm 1 3
free -h
uptime
```

| Signal | Concern |
|--------|---------|
| Data volume **> 85%** full | Compaction and writes may fail |
| Commitlog volume full | Node may refuse writes |
| High **iowait** sustained | Disk bottleneck |
| **Swap** in use | GC and latency suffer |
| Load >> CPU count sustained | CPU saturation |

Cassandra-specific paths vary (`cassandra.yaml` → `data_file_directories`, `commitlog_directory`). Know them for the deployment.

---

## 5) Logs — last 15 minutes tell the story

```bash
tail -200 /var/log/cassandra/system.log
grep -E 'ERROR|WARN|OutOfMemory|GC overhead|Compaction|hints' /var/log/cassandra/system.log | tail -50
```

Patterns worth stopping for:

- Repeated **GC overhead limit exceeded** or long **CMS/G1** pauses.
- **Compaction** failures or **Disk full**.
- **Hints** not replaying (node down a long time).
- **Streaming** errors during repair or bootstrap.

For HCD/DSE, also check product-specific logs if present.

---

## 6) JMX — live metrics without a dashboard

If JMX is enabled locally:

```bash
nodetool info
nodetool netstats
```

Or attach with `jconsole` / `nodetool sjk` if available.

Useful JMX families (names vary by version) — see [Key metrics to track](07-key-metrics.md) for the [triage flow](07-key-metrics.md#quick-triage-flow), [thresholds](07-key-metrics.md#suggested-targets), and full cheat sheet:

- `org.apache.cassandra.metrics:type=ClientRequest,*` — latencies and timeouts.
- `org.apache.cassandra.metrics:type=Compaction,*` — pending bytes, completed tasks.
- `org.apache.cassandra.metrics:type=Table,*` — per-table read/write rates.

You do not need every metric — one elevated **99th percentile** or timeout counter confirms what `tpstats` already hinted.

---

## 7) Five-line health summary

After the checks above, write:

1. **Membership:** (all UN / N down / bootstrap in flight)
2. **Backpressure:** (tpstats/compaction — clear or which pool)
3. **Disk:** (free % on data and commitlog)
4. **Logs:** (clean / top error theme)
5. **Next step:** (e.g. add capacity, repair node X, collect diagnostics)

Example:

> All 6 nodes UN in 2 DCs. Native-Transport-Requests pending 12 on node3. Data disk 78% on node3 only. Logs show compaction backlog on node3. Next: investigate node3 disk and table size skew; run diagnostic collection before change window.

---

## When this snapshot is enough

- Incident triage: confirm scope (one node vs whole cluster).
- Go/no-go before maintenance.
- Deciding whether to escalate to deeper analysis.

## When to go deeper

- Intermittent issues — need time-series metrics and historical logs.
- Schema or capacity planning — need SSTable stats and table-level detail.
- Cross-node comparison at scale — use [diagnostic collection](04-diagnostic-collection.md) and [Montecristo](06-montecristo-analysis.md).

➡️ **Kubernetes / Mission Control:** [Health snapshot — Kubernetes](02-health-snapshot-kubernetes.md)
