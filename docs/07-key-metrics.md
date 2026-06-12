# Key metrics to track

A practical cheat sheet for Cassandra / HCD health: what to watch, where to find it, and what rising values usually mean. Use this during a [live snapshot](01-health-snapshot-bare-metal.md) (steps **1a** / **1b**), when reviewing collector `metrics.jmx`, or in Grafana after Montecristo analysis.

You do not need every JMX bean — focus on **latency**, **errors**, **backpressure**, **compaction**, **hints**, **host resources**, and **JVM**.

**Three layers:** use **nodetool / OS** for live triage (§1–§9), **Mission Control Grafana** dashboards on K8s ([§10](#10-mission-control-dashboard-map)), and **collector + Montecristo** for point-in-time or trend review ([Where to read each layer](#where-to-read-each-layer)).

On Mission Control, panel names often include `$by` (per node/table/keyspace) and `$rate` (per-minute rate). Combine both for per-entity trends.

---

## Quick triage flow

Use this sequence during an incident (adapt for bare metal with nodetool where Grafana is unavailable):

1. **Availability** — Nodes Up/Down ([§6](#6-cluster-topology-and-repair)), **Dropped Messages**, **Client Timeouts** and **Unavailables** ([§2](#2-client-errors-and-sla-leaks)). Target: all nodes **UN**, error rates ~0.
2. **Latency up?** — Read/Write p99 ([§1](#1-client-request-latency-most-important)), GC pauses ([§5](#5-jvm-and-gc)), pending compactions ([§4](#4-compaction-and-disk)), **SSTables per read** ([§7](#7-per-table-signals-hot-spots)).
3. **Write issues?** — **Memtable Flusher** / **MutationStage** pending ([§3](#3-thread-pools--backpressure-nodetool-tpstats)), disk IO and iowait ([§9](#9-host-metrics-os--node)), pending compactions.
4. **Read timeouts?** — Tombstones scanned, SSTables per read, GC, IO wait.
5. **Inconsistency risk?** — Repair progress ([§6](#6-cluster-topology-and-repair)), hints backlog and hint delivery failures ([§8](#8-hints-hinted-handoff)).

Always correlate latency with GC, compaction, disk IO, and network before tuning CQL or JVM.

---

## Suggested targets

Use **planning** numbers for capacity reviews; **incident** numbers when triaging an outage.

| Signal | Planning (steady state) | Incident (investigate) |
|--------|-------------------------|-------------------------|
| Nodes up | 100% | Any unexpected down node |
| Client timeouts / unavailables / dropped messages | ~0 sustained | Any sustained non-zero under normal load |
| Read/Write latency p99 | Within SLA | Climbs while load is flat |
| GC pause (young/old) | Typically **< 200 ms** | Frequent pauses **> 200–500 ms** |
| JVM Old Gen / heap | **< ~70%** of max sustained | Rising Old Gen + long GC pauses |
| CPU busy | **< 70–80%** sustained | Pegged with rising latency |
| CPU iowait | **< ~5%** sustained | High with compaction/disk backlog |
| Disk utilization (data + compaction headroom) | **< 60–70%** for growth/repair | **> ~85%** on data or commitlog mount |
| Pending compactions | Low watermark returns | Grows linearly or never drains |
| SSTables per read / tombstones scanned | Low baseline | Sudden or sustained spike |
| Hints on disk / total hints | Drains after outage | Grows while all nodes **UN** |
| Full cluster repair | Within RPO (e.g. every 7–14 days) | Stalled or failing segments |

---

## 1) Client request latency (most important)

These measure how long the coordinator spends serving CQL reads and writes. Latency spikes here are what users feel first.

| Metric | JMX (`metrics.jmx`) | Grafana / Mimir (typical) | Investigate when |
|--------|------------------------|---------------------------|------------------|
| Read latency p50 / p95 / **p99** | `ClientRequest`, scope `Read` or `Read-ONE`, name `Latency` | **Coordinator Read Latency** / `$by` / `$rate` | p99 climbs while load is flat, or ms → tens/hundreds of ms |
| Write latency p50 / p95 / **p99** | `ClientRequest`, scope `Write`, name `Latency` | **Coordinator Write Latency** / `$by` / `$rate` | Same as reads; often coupled with compaction or disk |
| Range read latency | `ClientRequest`, scope `RangeSlice`, name `Latency` | **Coordinator Range Read Latency** / `$by` / `$rate` | High on wide partition scans or large IN queries |
| Request throughput | `ClientRequest` → `Latency` Count / rates | **Requests Served** / `$by` / `$rate` | Dip with steady client demand → contention or partial outage |
| LWT (CAS) latency | `CASRead`, `CASWrite`, `CASPrepare` | if exposed | Elevated during contention on lightweight transactions |

**Units:** JMX latencies are usually **microseconds** (µs). Divide by 1000 for milliseconds.

**Live checks:**

```bash
nodetool tpstats          # backpressure before latency shows in JMX
nodetool tablestats ks.t  # per-table read/write latency (when traffic exists)
```

**Correlation:** Rising p99 with high `ReadStage` / `MutationStage` **Pending** in `tpstats` → thread-pool saturation. Rising p99 with high compaction pending → disk/compaction backlog.

---

## 2) Client errors and SLA leaks

Latency can look fine while requests fail or time out.

| Metric | JMX scope / name | Meaning |
|--------|------------------|---------|
| **Timeouts** | `ClientRequest` → `Timeouts` | Coordinator waited too long (read/write/range) |
| **Unavailables** | `ClientRequest` → `Unavailables` | Not enough replicas alive for CL |
| **Failures** | `ClientRequest` → `Failures` | Unexpected errors on the request path |
| **UnfinishedCommit** | write path | Possible hint / write concern issues — see [§8](#8-hints-hinted-handoff) |
| **Dropped messages** | `DroppedMessage` (by verb) | Overload or timeouts on inter-node messaging |

**Mission Control panels:** **Client Timeouts** / `$by` / `$rate`, **Dropped Messages** / `$rate`, **Clients Connected** / `$by` (spikes may precede overload).

Track **Count** (total since restart) and **OneMinuteRate** / **FiveMinuteRate** (recent trend). Any sustained non-zero rate under normal load warrants investigation.

```bash
nodetool netstats    # streaming, repair, hints in flight
nodetool status      # UN vs DN / UJ
```

---

## 3) Thread pools — backpressure (nodetool `tpstats`)

| Pool | What it tells you |
|------|-------------------|
| **Native-Transport-Requests** | Client connection pressure — correlates with **Clients Connected** panel |
| **ReadStage** | Local read execution queue |
| **MutationStage** | Write / mutation queue |
| **MemtableFlushWriter** | Memtable flush backlog — MC: **Memtable Flusher TP Stats**, **Flushes Pending** |
| **CompactionExecutor** | Compactions waiting for CPU/disk |
| **HintsDispatcher** | Hint delivery backlog — see [§8](#8-hints-hinted-handoff) |

Watch **Pending** and **Blocked** — not just **Active**. Occasional pending is normal; sustained hundreds/thousands with rising latency is not. Write-path triage: check **Memtable Flusher** and **MutationStage** before blaming compaction alone.

JMX mirror: `ThreadPools` → `CurrentlyBlockedTasks`, `PendingTasks`, `ActiveTasks` per scope.

---

## 4) Compaction and disk

| Metric | Source | Investigate when |
|--------|--------|------------------|
| Pending compaction tasks | `nodetool compactionstats` | Many tasks stuck; one huge task |
| Pending compaction bytes | JMX `Compaction` → `PendingBytes` | Grows without clearing — MC: **Pending Compactions**/node/`$rate` |
| Completed compaction rate | JMX `Compaction` → `Completed` | Drops to zero under write load — MC: **Completed Compactions**, **Compactions**/`$rate` |
| Compacted throughput | JMX `Compaction` → `BytesCompacted` | Spikes after heavy writes or repairs — MC: **Compacted Bytes**/node/`$rate` |
| Live data size | JMX `ColumnFamily` / table stats | Growth vs capacity — MC: **Live Data Size**, **Live Disk Space Used** / `$by` |
| SSTable count per table | `nodetool tablestats` | Grows without compaction keeping pace |
| Disk used / free | `df`, PVC usage, `Storage` JMX | **> ~85%** incident; plan headroom **< 60–70%** ([targets](#suggested-targets)) |
| Commitlog disk | `df`, config paths | Full commitlog → write stops |

Host-level disk, CPU, and memory: [§9 Host metrics](#9-host-metrics-os--node).

```bash
nodetool compactionstats
nodetool getcompactionthroughput
nodetool tablestats
```

---

## 5) JVM and GC

| Metric | Source | Investigate when |
|--------|--------|------------------|
| Heap used / max | JMX `memory` / `GarbageCollector` | Near max sustained; Old Gen **> ~70%** sustained → tuning |
| G1 pool churn | JMX `memory` pools | Eden/Survivor churn — MC: **JVM G1 Eden/Old Gen/Survivor** used/node |
| GC pause time | `logs/gc.log`, GC JMX | Target **< 200 ms** typical; investigate **> 200–500 ms** |
| CMS / G1 old-gen time | GC logs | `GC overhead limit exceeded` in system.log |

```bash
grep -E 'GC|Pause' logs/gc.log | tail -20   # from collector bundle
grep -E 'OutOfMemory|GC overhead' logs/system.log
```

Mission Control / Grafana: **JVM GC Young Gen** / **Old Gen** / **Old Gen Count** /node/`$rate`, plus heap pool panels above. Correlate GC spikes with read/write p99 in Loki (`gc.log`) or MC charts.

---

## 6) Cluster topology and repair

| Signal | Command / metric | Concern |
|--------|------------------|---------|
| Node state | `nodetool status` | Non-**UN** nodes — MC: **Nodes Up**, **Nodes Down** |
| Ownership skew | `nodetool describering` | Token imbalance after expand/shrink |
| Streaming | `nodetool netstats`, JMX `Streaming` | Stuck streams — MC: **Streaming Incoming/Outgoing Bytes** / `$by`/sec |
| Repair (scheduled) | JMX `Repair` / `Validation` | Failed or never-completing repair — MC: **Repairs Completed** / `$by`/`$rate` |
| Read repair | JMX `ReadRepair` | Surges suggest drift — MC: **Read Repair Requests** / `$by`/`$rate` |
| Inter-DC latency | JMX `Messaging`, `<DC>-Latency` | High cross-DC wait affects CL — see [inter-DC](#inter-datacenter-messaging) |

**Repair RPO:** complete a full cluster repair within your policy window (e.g. every 7 or 14 days). Track **Repairs Completed** rate against that goal.

See [§8 Hints](#8-hints-hinted-handoff) when a node was down or flapping.

### Inter-datacenter messaging

Inter-DC latency metrics require `cross_node_timeout: true` in `cassandra.yaml`. JMX: `org.apache.cassandra.metrics:type=Messaging,name=<DC-Name>-Latency`. In Mimir/Grafana these become names like `org_apache_cassandra_metrics_messaging_dc1_latency`. No bundled MC dashboard — build a custom panel per peer DC.

---

## 7) Per-table signals (hot spots)

When you know the keyspace/table:

| Metric | Source | MC panel (typical) |
|--------|--------|-------------------|
| Read / write request rate | JMX `ColumnFamily` rates | **Read Requests/Table**, **Write Requests/Table** |
| Read / write latency | `tablestats` → `Read latency`, `Write latency` | Per-table latency in Explore |
| SSTables per read | JMX / table stats | **SSTables Per Read** / `$by` |
| Tombstones per read | `tablestats` → `Tombstone per read` | **Tombstones Scanned** / `$by` |
| Live SSTables / disk | `tablestats` → space used | **Live Disk Space Used** / `$by` |
| Partition size | `nodetool tablehistograms` (if enabled) | — |

---

## 8) Hints (hinted handoff)

When a replica is temporarily unreachable, coordinators store **hints** — deferred writes — and replay them when the node returns. A small backlog after a brief outage is normal. A **large or growing** backlog means data may be stale on that replica until hints drain (or repair catches up).

### What to watch

| Metric / signal | Source | Investigate when |
|-----------------|--------|------------------|
| **TotalHints** | JMX `Storage` → `TotalHints` | Count rising while all nodes are **UN** — MC: **Total Hints** |
| **Hints on disk** | JMX / filesystem | MC: **Hints on Disk** / `$by`/`$rate` |
| **Hint delivery** | JMX hint service counters | MC: **Hints Succeeded**, **Hints Failed**, **Hint Delays** / `$by`/`$rate` |
| **TotalHintsInProgress** | JMX `Storage` → `TotalHintsInProgress` | Stuck > 0 for a long time after node recovered |
| **HintsInProgress** | JMX `StorageProxy` → `HintsInProgress` | Same — active replay not finishing |
| **HintsDispatcher** pending / blocked | `nodetool tpstats`, JMX `ThreadPools` scope `HintsDispatcher` | Sustained **Pending** or **Blocked** |
| **Hints_for_unowned_ranges** | JMX `HintsService` | Non-zero after topology change (tokens moved) |
| **Dropped** (HINT_REQ / HINT_RSP) | JMX `DroppedMessage` | Hint messages dropped under load |
| **HINT_REQ-WaitLatency** p99 | JMX `Messaging` | High wait → network or receiver overload |
| On-disk hint size | `du -sh` on `hints_directory` from `cassandra.yaml` | GB-scale growth while node is up |
| Log patterns | `system.log` | `Hinted handoff`, replay errors, expired hints |

**Config checks** (from collector `conf/cassandra.yaml` or JMX `StorageProxy`):

- `hinted_handoff_enabled` / `HintedHandoffEnabled` — should be **true** in most clusters
- `max_hint_window_in_ms` / `MaxHintWindow` — how long hints are kept (default often 3 h)
- `hints_directory` — disk must not fill

### Live commands

```bash
nodetool status                    # any DN/UJ node → expect hints to that host
nodetool tpstats                   # HintsDispatcher row
nodetool netstats                  # streaming / repair context alongside hints
du -sh /var/lib/cassandra/hints    # path from cassandra.yaml
grep -i hint /var/log/cassandra/system.log | tail -30
```

From a collector bundle:

```bash
grep -E 'TotalHints|HintsInProgress|HintsDispatcher|Hints_for_unowned' extracted/*/metrics.jmx
grep -i hint extracted/*/nodetool/*.txt extracted/*/logs/system.log | tail -30
grep -E 'hinted_handoff|hints_directory|max_hint_window' extracted/*/conf/cassandra.yaml
```

### How to read the situation

| Pattern | Likely meaning |
|---------|----------------|
| Spike in **TotalHints** during outage, drains after **UN** | Healthy hinted handoff |
| **TotalHintsInProgress** high, target node **UN** | Replay in progress — watch disk and tpstats |
| Backlog grows while **all nodes UN** | Replay stuck — check logs, disk, `HintsDispatcher`, network |
| Hints after decommission / move | May need repair; check `Hints_for_unowned_ranges` |
| `hint window` expired in logs | Some writes lost for CL — confirm with repair |

**Write path link:** rising **UnfinishedCommit** or write **Timeouts** during an outage often correlate with hint pressure once nodes recover.

---

## 9) Host metrics (OS / node)

Cassandra is sensitive to disk, memory, and clock quality. JVM metrics (§5) show heap pressure; **host metrics** show whether the node itself is healthy. Montecristo's infrastructure section flags many of these from collector bundles.

### CPU and load

| Metric | Live source | Collector bundle | Investigate when |
|--------|-------------|------------------|------------------|
| **Load average** (1 / 5 / 15 m) | `uptime`, `top` | `os/uptime.txt`, `os/top.txt` | Sustained load **>> CPU count** (see `os/lscpu.txt`) |
| **CPU utilization** | `top`, `vmstat` | `os/vmstat.txt`, `os/ps-aux.txt` | User + system pegged with rising latency |
| **iowait %** | `iostat -xm`, `vmstat` | `os/vmstat.txt` (wa column) | Sustained high iowait → disk bottleneck |
| **CPU steal** (cloud) | `top`, `/proc/stat` | `os/cpuinfo`, `os/vmstat.txt` | Non-zero steal → noisy neighbor / undersized VM |
| **Context switches** | `vmstat` | `os/vmstat.txt` | Extreme churn with high load |

```bash
uptime
nproc
iostat -xm 1 3
vmstat 1 3
grep -E 'processor|model name' os/lscpu.txt   # from bundle
```

### Memory and swap

| Metric | Live source | Collector bundle | Investigate when |
|--------|-------------|------------------|------------------|
| **Available memory** | `free -h` | `os/free.txt` | **Available** near zero sustained |
| **Swap used** | `free -h`, `swapon -s` | `os/free.txt`, `os/slaptop.txt` | Any swap use on a Cassandra node (avoid) |
| **OOM / kill** | `dmesg`, `system.log` | `logs/system.log` | OOM killer or `OutOfMemoryError` |

Cassandra relies on OS page cache for reads; memory pressure hurts both heap (GC) and cache effectiveness.

### Disk and I/O

| Metric | Live source | Collector bundle | Investigate when |
|--------|-------------|------------------|------------------|
| **Data volume use %** | `df -h` | `storage/df-size.txt` | **> ~85%** on `data_file_directories` mount |
| **Inode use %** | `df -i` | `storage/df-inode.txt` | Near 100% — creates/compactions fail |
| **Disk latency / util** | `iostat -xm` | (live only unless dstat collected) | `%util` ~100% or high `await` ms |
| **Block devices** | `lsblk` | `os/lsblk.txt`, `os/lsblk_custom.txt`, `os-metrics/disk_device.txt` | Wrong device or shared disk with other workloads |
| **Read-ahead / scheduler** | `blockdev`, sysfs | `os/blockdev-report.txt` | Suboptimal RA for SSD (Montecristo may flag) |

Map `df` output to paths in `conf/cassandra.yaml`: `data_file_directories`, `commitlog_directory`, `saved_caches_directory`, `hints_directory`.

```bash
df -h /var/lib/cassandra
df -i /var/lib/cassandra
iostat -xm 1 3
du -sh /var/lib/cassandra/data/* | sort -h | tail
```

### Network

| Metric | Live source | Collector bundle | Investigate when |
|--------|-------------|------------------|------------------|
| **Open connections** | `ss -s`, `ss -tan` | `os/ss.txt` | Connection storms, many CLOSE_WAIT |
| **Link errors / drops** | `ethtool -S` | `network/ethtool-*.txt` | Non-zero error counters |
| **Inter-node latency** | `nodetool gossipinfo` | `nodetool/gossipinfo.txt` | Cross-DC latency affecting CL |

### Time, kernel, and limits

| Metric | Live source | Collector bundle | Investigate when |
|--------|-------------|------------------|------------------|
| **NTP / clock sync** | `ntpq -p`, `chronyc` | `os/date.txt`, Montecristo NTP checks | Clock drift → consistency and TTL issues |
| **File descriptors / ulimits** | `ulimit -n` | `os/limits.conf`, `os/limits.d/` | Too low for high connection counts |
| **Transparent huge pages** | sysfs | `os/transparent_hugepage-*.txt` | `always` on can hurt latency |
| **NUMA layout** | `numactl --hardware` | `os/numactl-hardware.txt` | Wrong heap / disk NUMA pairing |

### Kubernetes mapping

On Mission Control / KinD, host metrics come from the **node and pod** observability stack rather than SSH:

| Bare metal | Kubernetes + Mission Control |
|------------|------------------------------|
| `free`, `uptime`, `iostat` | **Mission Control System & Node Metrics**: **CPU Busy**, **CPU Basic**, **Memory Used**, **Memory Basic** |
| CPU breakdown | **CPU User**, **CPU System**, **CPU IOWait**, **CPU Other** |
| Disk IO | **Disk Rate per second**, **Disk IOPS** |
| Network | **Network Traffic Basic**, **Network Packets** |
| `df` on data path | **Used Root FS**, **Disk Used** + PVC usage |
| Per-container CPU/mem | Pod metrics in MC UI |

See [K8s health snapshot §5](02-health-snapshot-kubernetes.md#5-observability-pipeline--metrics-and-logs) and mc-lab [Observability](https://github.com/datastax/mc-lab/blob/main/docs/05-observability.md).

### Quick review from a collector tarball

```bash
# Per-node snapshot (after extract or under ./ds-discovery/.../extracted/)
cat extracted/*/os/uptime.txt extracted/*/os/free.txt
grep -E '/var/lib/cassandra|/data|cassandra' extracted/*/storage/df-size.txt
head extracted/*/os/vmstat.txt
grep -i hugepage extracted/*/os/transparent_hugepage-*.txt
```

**Correlation with Cassandra metrics:** high **iowait** + high **Compaction pending bytes** → disk-bound compactions. High **load** + high **ReadStage** pending → CPU saturation. **Swap used** + rising **GC pauses** → fix memory sizing before tuning JVM.

---

## 10) Mission Control dashboard map

Mission Control ships two primary Grafana dashboards for database health:

| Dashboard | Use for |
|-----------|---------|
| **Mission Control Cluster** | Cassandra JMX: latency, errors, compaction, hints, repair, JVM |
| **Mission Control System & Node Metrics** | Host/node: CPU, memory, disk IO, network (node exporter) |

### KPI → panel → nodetool / JMX

| KPI | MC panel(s) | nodetool / JMX / bundle |
|-----|-------------|-------------------------|
| Nodes up/down | **Nodes Up**, **Nodes Down** | `nodetool status` |
| Request throughput | **Requests Served** / `$by` / `$rate` | `ClientRequest` latency Count |
| Read/write/range latency | **Coordinator Read/Write/Range Read Latency** / `$by` / `$rate` | `ClientRequest` → `Latency` percentiles |
| Client errors | **Client Timeouts**, **Dropped Messages** / `$rate` | `Timeouts`, `Unavailables`, `DroppedMessage` |
| Client connections | **Clients Connected** / `$by` | `tpstats` → Native-Transport-Requests |
| Thread pool backlog | **Memtable Flusher TP Stats**, **Flushes Pending** | `nodetool tpstats` (all pools) |
| Compaction backlog | **Pending Compactions**/node/`$rate` | `compactionstats`, `PendingBytes` |
| Compaction throughput | **Completed Compactions**, **Compacted Bytes** | JMX `Compaction` |
| Live data / disk | **Live Data Size**, **Live Disk Space Used** | `tablestats`, `df` / `storage/df-size.txt` |
| Read efficiency | **SSTables Per Read**, **Tombstones Scanned** | `tablestats`, per-table JMX |
| Table hotspots | **Read/Write Requests/Table** | JMX `ColumnFamily` rates |
| Hints | **Total Hints**, **Hints on Disk**, **Hints Succeeded/Failed/Delays** | §8 JMX + `du` on `hints/` |
| Streaming | **Streaming Incoming/Outgoing Bytes** | `nodetool netstats` |
| Repair | **Repairs Completed**, **Read Repair Requests** | JMX `Repair`, `ReadRepair` |
| JVM / GC | **JVM G1** pools, **JVM GC** young/old/count | `gc.log`, GC JMX |
| Host CPU/memory/disk | **CPU Busy**, **Memory Basic**, **Disk Used**, **Disk IOPS** | §9 `os/*`, `storage/*` |

### Other monitoring

| Topic | Notes |
|-------|--------|
| **TLS certificate expiry** | UMS Certificate Expiry Detector (production MC deployments) — prevents handshake failures from expired certs |
| **Alerting** | Define alerts on timeouts, nodes down, disk, and hint backlog — see [DataStax metrics and alerts](https://docs.datastax.com/en/planning/dse/metrics-alerts.html) |
| **Logs** | Use Loki in MC/Grafana to correlate GC pauses and `system.log` errors with metric spikes ([K8s snapshot §5](02-health-snapshot-kubernetes.md#5-observability-pipeline--metrics-and-logs)) |

---

## Where to read each layer

| Layer | When | Where |
|-------|------|--------|
| **Live triage** | Incident now | `nodetool`, `tpstats`, Grafana Explore ([K8s snapshot](02-health-snapshot-kubernetes.md)) |
| **Point-in-time bundle** | Post-incident / support | Collector `metrics.jmx`, `nodetool/*.txt`, `os/*`, `storage/*` in tarball |
| **Trend + rules** | Deep review | [Montecristo](06-montecristo-analysis.md) `metrics.db` + report |
| **Quick log scan** | Before Montecristo | Extract tarballs under `./diagnostics/` and grep `system.log` ([doc 04](04-diagnostic-collection.md#quick-log-triage-optional)) |

### Grep `metrics.jmx` from a tarball (logs only extracted)

```bash
# see docs/04-diagnostic-collection.md — quick log triage on ./diagnostics/
grep 'ClientRequest.*Read.*99thPercentile' extracted/*/metrics.jmx
grep 'ClientRequest.*Write.*99thPercentile' extracted/*/metrics.jmx
grep 'PendingBytes' extracted/*/metrics.jmx
grep -E 'TotalHints|TotalHintsInProgress|HintsInProgress' extracted/*/metrics.jmx
grep -E 'load average|Swap:|Mem:' extracted/*/os/{uptime,free}.txt
grep -E 'Use%|/cassandra|/data' extracted/*/storage/df-size.txt
```

Or after Montecristo extraction:

```bash
grep 'ClientRequest.*Latency.*99thPercentile' ./ds-discovery/<issue>/extracted/*/metrics.jmx
```

---

## Minimum dashboard set (Grafana / Mission Control)

If you can only keep a handful of panels (names from **Mission Control Cluster** + **System & Node Metrics**):

1. **Nodes Up** / **Nodes Down**
2. **Coordinator Read Latency** and **Coordinator Write Latency** p99 / `$by`
3. **Client Timeouts** + **Dropped Messages** / `$rate` (+ **Unavailables** in Explore if not charted)
4. **Requests Served** / `$rate` (throughput dip detector)
5. **Pending Compactions** + **Compacted Bytes** / `$rate`
6. **JVM G1 Old Gen** used + **JVM GC Old Gen** pause / `$rate`
7. **Live Data Size** + **Disk Used** (cluster) + **CPU IOWait** (node dashboard)
8. **Total Hints** + **Hints Failed** / `$rate` + **Memtable Flusher TP Stats**
9. **SSTables Per Read** + **Tombstones Scanned** (when read latency is the symptom)

---

## How this ties to the training path

| Step | Metrics use |
|------|-------------|
| [01 Bare-metal snapshot](01-health-snapshot-bare-metal.md) | `tpstats`, `compactionstats`, JMX, OS checks (§4 storage, §9 host) |
| [02 K8s snapshot](02-health-snapshot-kubernetes.md) | MC Cluster + System & Node dashboards, Loki ([§10](#10-mission-control-dashboard-map)) |
| [03 Local lab](03-local-lab.md) | Stress before collector for non-empty `cfstats` / latencies |
| [04 Diagnostic collection](04-diagnostic-collection.md) | Full `metrics.jmx` snapshot per node |
| [05 sperf](05-sperf-analysis.md) | CLI summaries from collector layout |
| [06 Montecristo](06-montecristo-analysis.md) | Parses JMX into `metrics.db`; report flags config and ops issues |

---

## Related reading

- Apache Cassandra metrics: [Metric types](https://cassandra.apache.org/doc/latest/cassandra/operating/metrics.html) (upstream)
- DataStax [Important metrics and alerts](https://docs.datastax.com/en/planning/dse/metrics-alerts.html) — KPI thresholds and alerting guidance
- mc-lab [Observability](https://github.com/datastax/mc-lab/blob/main/docs/05-observability.md) — Mission Control metrics pipeline on KinD
