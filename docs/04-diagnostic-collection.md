# Diagnostic collection

When a health snapshot is not enough — intermittent issues, capacity review, or support escalation — collect a **diagnostic snapshot** from every node with the [DataStax Diagnostic Collector](https://github.com/datastax/diagnostic-collection).

The collector produces per-node tarballs (optionally encrypted) containing configuration, logs, nodetool output, JMX metrics, schema, SSTable statistics, and OS information.

---

## What gets collected

From each node (see upstream [README](https://github.com/datastax/diagnostic-collection/blob/master/ds-collector/README.md)):

- `cassandra.yaml`, `dse.yaml`, JVM options
- Cassandra/HCD logs
- `nodetool` / `dsetool` output (`status`, `ring`, `tablestats`, `tpstats`, …)
- JMX metrics snapshot
- Keyspace/schema CQL
- SSTable `Statistics.db` files
- OS: CPU, memory, disk, limits, NTP, block devices

No sensitive application data (row contents) are collected. An `audit.log` lists commands run on each node.

---

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| **Jump box** | Bastion host — **not** a Cassandra pod/node |
| **Network** | SSH, Docker API, or `kubectl` access to all targets |
| **Bundle** | Download latest `ds-collector.GENERIC-*.tar.gz` from [releases](https://github.com/datastax/diagnostic-collection/releases) |

---

## Local lab — test Cassandra container

Practice the collector on your workstation before touching production or KinD. A single-node Cassandra container exercises the **Docker** code path (`use_docker="true"`) — no SSH or kubeconfig required.

**Prerequisite:** complete [Local lab](03-local-lab.md) (start container, optional `./scripts/lab-stress.sh`).

### 1) Extract the collector bundle

```bash
tar -xvf ds-collector.GENERIC-*.tar.gz
cd collector
chmod +x ds-collector
```

### 2) Configure for Docker

From the **repository root**, create the collector output directory. Artifacts are written to `./diagnostics/` (gitignored), not `/tmp/datastax`.

```bash
mkdir -p diagnostics
cd collector
cp collector.conf collector.conf.bak
sed -i 's/^#use_docker=.*/use_docker="true"/' collector.conf
sed -i 's/^#skipSudo=.*/skipSudo="true"/' collector.conf
sed -i 's/^#?keepArtifact=.*/keepArtifact="true"/' collector.conf
sed -i "s|^#?bastionBaseDir=.*|bastionBaseDir=\"$(cd .. && pwd)/diagnostics\"|" collector.conf
```

`skipS3` is already `true` in the training bundle.

### 3) Test and collect (single node)

Use the **container name** as the contact node and `-d` so discovery does not look for peers that do not exist:

```bash
# Test
./ds-collector -T -d -f collector.conf -n ds-collector-test-cassandra

# Execute
./ds-collector -X -d -f collector.conf -n ds-collector-test-cassandra
```

Artifacts appear under `./diagnostics/`:

```bash
ls -lh ../diagnostics/*.tar.gz    # from collector/
# or, from repo root:
ls -lh ./diagnostics/*.tar.gz
```

---

## VM / bare metal workflow

### 1) Extract and configure

```bash
tar -xvf ds-collector.GENERIC-*.tar.gz
cd collector
chmod +x ds-collector
```

Edit `collector.conf`:

- SSH user/key or password for Cassandra nodes
- `is_dse=true` for DSE/HCD if applicable
- Optional: `keepArtifact="true"`, `skipS3="true"` for local-only bundles

### 2) Test connectivity

```bash
./ds-collector -T -f collector.conf -n <CASSANDRA_CONTACT_NODE>
```

Resolve any `NOTOK` lines before collecting (see upstream [TROUBLESHOOTING.md](https://github.com/datastax/diagnostic-collection/blob/master/ds-collector/TROUBLESHOOTING.md)).

### 3) Collect

```bash
./ds-collector -X -f collector.conf -n <CASSANDRA_CONTACT_NODE>
```

Artifacts land under the configured `bastionBaseDir` (training default: `./diagnostics/`) as:

```
<hostname>_artifacts_<timestamp>.tar.gz
```

For local analysis without S3:

```bash
sed -i 's/^#?keepArtifact=.*/keepArtifact="true"/' collector.conf
sed -i 's/^#?skipS3=.*/skipS3="true"/' collector.conf
```

### 4) Single node or subset

```bash
# One node only
./ds-collector -X -d -f collector.conf -n <NODE>

# Explicit host list (skip discovery)
./ds-collector -X -d -f collector.conf -n collector.hosts
```

---

## Kubernetes / Mission Control workflow

For clusters on Kubernetes, build or download a collector bundle with **`is_k8s=true`** (set at build time per upstream docs), or configure `collector.conf` for kubectl execution.

### Configuration highlights

| Setting | Purpose |
|---------|---------|
| `is_k8s=true` | Run commands via `kubectl exec` instead of SSH |
| `k8s_namespace` | Namespace of Cassandra pods (e.g. `database`) |
| `k8s_label_selector` | Label query to find pods (e.g. cluster name) |

Example label selector for mc-lab:

```
cassandra.datastax.com/cluster=two-dcs
```

### Run from jump box with kubeconfig

```bash
export KUBECONFIG=/path/to/kubeconfig

./ds-collector -T -f collector.conf -n <any-ready-pod-dns-or-contact>
./ds-collector -X -f collector.conf -n <contact>
```

The collector discovers peer pods via nodetool/gossip and collects from each.

### KinD lab tips

1. Run the collector on your workstation (not inside KinD) with kubeconfig pointing at the lab cluster.
2. Ensure `kubectl get pods -n database` shows all Cassandra pods **Running**.
3. Keep artifacts on the host: `keepArtifact="true"` and `skipS3="true"`.
4. Copy the output directory to your analysis machine if different from the jump box.

```bash
# After collection (repo root)
ls ./diagnostics/*.tar.gz
```

---

## Encrypted artifacts

Some builds ship with an encryption key (`<PROJECT_ID>_secret.key`). Place it next to `ds-collector` before collection, or supply it to Montecristo during analysis.

---

## Quality checks before analysis

Quick peek inside one tarball:

```bash
tar -tzf ./diagnostics/node1_artifacts_*.tar.gz | head -30
```

Expect paths like `nodetool/`, `conf/`, `logs/`, `metrics.jmx`.

---

## Quick log triage (optional)

Right after collection, you can grep `system.log` for a fast sanity check. Tarballs must be extracted first (`grep` cannot read inside `*.tar.gz` directly).

Extract collector output, then grep:

```bash
mkdir -p ./diagnostics/log-triage
for t in ./diagnostics/*_artifacts_*.tar.gz; do
  tar -tzf "$t" | grep -E '/logs/.+' | tar -xzf "$t" -C ./diagnostics/log-triage -T -
done
cd ./diagnostics/log-triage

find . -name "system.log*" -print0 | xargs -0 grep -e 'ERROR' | grep -v 'tombstone cells for query' > errors.log
find . -name "system.log*" -print0 | xargs -0 grep -e 'WARN'  | grep -v 'tombstone cells for query' > warnings.log
find . -name "system.log*" -print0 | xargs -0 grep -e 'gc'    | grep -v 'tombstone cells for query' > gc-from-system.log
find . -name "system.log*" -print0 | xargs -0 grep -e 'ERROR\|WARN' | grep 'tombstone cells for query' > errors-tombstones.log
```

---

➡️ **Next:** [sperf analysis](05-sperf-analysis.md) · [Montecristo analysis](06-montecristo-analysis.md)
