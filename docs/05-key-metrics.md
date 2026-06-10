# Key metrics to track

A practical cheat sheet for Cassandra / HCD health: what to watch, where to find it, and what rising values usually mean. Use this during a [live snapshot](01-health-snapshot-bare-metal.md) (steps **1a** / **1b**), when reviewing collector `metrics.jmx`, or in Grafana after Montecristo analysis.

You do not need every JMX bean — focus on **latency**, **errors**, **backpressure**, **compaction**, **hints**, **host resources**, and **JVM**.

---

## 1) Client request latency (most important)

These measure how long the coordinator spends serving CQL reads and writes. Latency spikes here are what users feel first.

| Metric | JMX (`metrics.jmx`) | Grafana / Mimir (typical) | Investigate when |
|--------|------------------------|---------------------------|------------------|
| Read latency p50 / p95 / **p99** | `ClientRequest`, scope `Read` or `Read-ONE`, name `Latency` | `cassandra_client_request_latency` (by quantile) | p99 climbs while load is flat, or ms → tens/hundreds of ms |
| Write latency p50 / p95 / **p99** | `ClientRequest`, scope `Write`, name `Latency` | same family, `write` | Same as reads; often coupled with compaction or disk |
| Range read latency | `ClientRequest`, scope `RangeSlice`, name `Latency` | dashboard “range” / scan panels | High on wide partition scans or large IN queries |
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

Track **Count** (total since restart) and **OneMinuteRate** / **FiveMinuteRate** (recent trend). Any sustained non-zero rate under normal load warrants investigation.

```bash
nodetool netstats    # streaming, repair, hints in flight
nodetool status      # UN vs DN / UJ
```

---

## 3) Thread pools — backpressure (nodetool `tpstats`)

| Pool | What it tells you |
|------|-------------------|
| **Native-Transport-Requests** | Client connection pressure |
| **ReadStage** | Local read execution queue |
| **MutationStage** | Write / mutation queue |
| **CompactionExecutor** | Compactions waiting for CPU/disk |
| **HintsDispatcher** | Hint delivery backlog — see [§8](#8-hints-hinted-handoff) |

Watch **Pending** and **Blocked** — not just **Active**. Occasional pending is normal; sustained hundreds/thousands with rising latency is not.

JMX mirror: `ThreadPools` → `CurrentlyBlockedTasks`, `PendingTasks`, `ActiveTasks` per scope.

---

## 4) Compaction and disk

| Metric | Source | Investigate when |
|--------|--------|------------------|
| Pending compaction tasks | `nodetool compactionstats` | Many tasks stuck; one huge task |
| Pending compaction bytes | JMX `Compaction` → `PendingBytes` | Grows without clearing |
| Completed compaction rate | JMX `Compaction` → `Completed` | Drops to zero under write load |
| SSTable count per table | `nodetool tablestats` | Grows without compaction keeping pace |
| Disk used / free | `df`, PVC usage, `Storage` JMX | **> ~85%** on data volume |
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
| Heap used / max | JMX `memory` / `GarbageCollector` | Near max sustained |
| GC pause time | `logs/gc.log`, GC JMX | Frequent pauses > 200–500 ms |
| CMS / G1 old-gen time | GC logs | `GC overhead limit exceeded` in system.log |

```bash
grep -E 'GC|Pause' logs/gc.log | tail -20   # from collector bundle
grep -E 'OutOfMemory|GC overhead' logs/system.log
```

Mission Control / Grafana: **JVM heap**, **GC pause**, **allocation rate** panels.

---

## 6) Cluster topology and repair

| Signal | Command / metric | Concern |
|--------|------------------|---------|
| Node state | `nodetool status` | Non-**UN** nodes |
| Ownership skew | `nodetool describering` | Token imbalance after expand/shrink |
| Streaming | `nodetool netstats` | Stuck streams during rebuild |
| Repair | JMX `Repair` / `Validation` | Failed or never-completing repair |

See [§8 Hints](#8-hints-hinted-handoff) when a node was down or flapping.

---

## 7) Per-table signals (hot spots)

When you know the keyspace/table:

| Metric | Source |
|--------|--------|
| Read / write latency | `tablestats` → `Read latency`, `Write latency` |
| Live SSTables / disk | `tablestats` → space used |
| Tombstones per read | `tablestats` → `Tombstone per read` (high → compaction or TTL issue) |
| Partition size | `nodetool tablehistograms` (if enabled) |

---

## 8) Hints (hinted handoff)

When a replica is temporarily unreachable, coordinators store **hints** — deferred writes — and replay them when the node returns. A small backlog after a brief outage is normal. A **large or growing** backlog means data may be stale on that replica until hints drain (or repair catches up).

### What to watch

| Metric / signal | Source | Investigate when |
|-----------------|--------|------------------|
| **TotalHints** | JMX `Storage` → `TotalHints` | Count rising while all nodes are **UN** |
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
| `free`, `uptime`, `iostat` | Node exporter → Mimir (`node_cpu_*`, `node_memory_*`, `node_disk_*`) |
| `df` on data path | PVC usage + node disk panels in Grafana |
| `ss` / network | cAdvisor / node network metrics |
| Per-container CPU/mem | Pod metrics in MC UI |

See [K8s health snapshot §5](02-health-snapshot-kubernetes.md#5-observability-pipeline--metrics-and-logs) and mc-lab [Observability](https://github.com/datastax/mc-lab/blob/main/docs/05-observability.md).

### Quick review from a collector tarball

```bash
# Per-node snapshot (after extract or under ~/ds-discovery/.../extracted/)
cat extracted/*/os/uptime.txt extracted/*/os/free.txt
grep -E '/var/lib/cassandra|/data|cassandra' extracted/*/storage/df-size.txt
head extracted/*/os/vmstat.txt
grep -i hugepage extracted/*/os/transparent_hugepage-*.txt
```

**Correlation with Cassandra metrics:** high **iowait** + high **Compaction pending bytes** → disk-bound compactions. High **load** + high **ReadStage** pending → CPU saturation. **Swap used** + rising **GC pauses** → fix memory sizing before tuning JVM.

---

## Where to read each layer

| Layer | When | Where |
|-------|------|--------|
| **Live triage** | Incident now | `nodetool`, `tpstats`, Grafana Explore ([K8s snapshot](02-health-snapshot-kubernetes.md)) |
| **Point-in-time bundle** | Post-incident / support | Collector `metrics.jmx`, `nodetool/*.txt`, `os/*`, `storage/*` in tarball |
| **Trend + rules** | Deep review | [Montecristo](04-montecristo-analysis.md) `metrics.db` + report |
| **Quick log scan** | Before Montecristo | [grep-logs helper](../scripts/grep-logs.sh) on `/tmp/datastax` |

### Grep `metrics.jmx` from a tarball (logs only extracted)

```bash
./scripts/grep-logs.sh /tmp/datastax   # logs
grep 'ClientRequest.*Read.*99thPercentile' extracted/*/metrics.jmx
grep 'ClientRequest.*Write.*99thPercentile' extracted/*/metrics.jmx
grep 'PendingBytes' extracted/*/metrics.jmx
grep -E 'TotalHints|TotalHintsInProgress|HintsInProgress' extracted/*/metrics.jmx
grep -E 'load average|Swap:|Mem:' extracted/*/os/{uptime,free}.txt
grep -E 'Use%|/cassandra|/data' extracted/*/storage/df-size.txt
```

Or after Montecristo extraction:

```bash
grep 'ClientRequest.*Latency.*99thPercentile' ~/ds-discovery/<issue>/extracted/*/metrics.jmx
```

---

## Minimum dashboard set (Grafana / Mission Control)

If you can only keep a handful of panels:

1. **Read p99** and **Write p99** (cluster + per DC)
2. **Timeouts** + **Unavailables** (rate)
3. **Compaction pending bytes**
4. **JVM heap used** + **GC pause**
5. **Disk usage** per node / PVC + **iowait** / disk latency
6. **Host CPU & memory** — load, available RAM, swap (node exporter on K8s)
7. **Hint backlog** — `TotalHints`, `TotalHintsInProgress`, on-disk `hints/` size
8. **tpstats-style** pending (or blocked tasks JMX)

---

## How this ties to the training path

| Step | Metrics use |
|------|-------------|
| [1a Bare-metal snapshot](01-health-snapshot-bare-metal.md) | `tpstats`, `compactionstats`, JMX, OS checks (§4 storage, §9 host) |
| [1b K8s snapshot](02-health-snapshot-kubernetes.md) | Mimir dashboards, Loki for GC/log correlation |
| [2 Diagnostic collection](03-diagnostic-collection.md) | Full `metrics.jmx` snapshot per node |
| [3 Montecristo](04-montecristo-analysis.md) | Parses JMX into `metrics.db`; report flags config and ops issues |

---

## Related reading

- Apache Cassandra metrics: [Metric types](https://cassandra.apache.org/doc/latest/cassandra/operating/metrics.html) (upstream)
- mc-lab [Observability](https://github.com/datastax/mc-lab/blob/main/docs/05-observability.md) — Mission Control metrics pipeline
