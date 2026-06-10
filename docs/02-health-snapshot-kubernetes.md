# Health snapshot — Kubernetes and Mission Control

On Kubernetes, Cassandra/HCD runs inside pods reconciled by operators. The health questions are the same as on bare metal, but you inspect **custom resources, pods, and the Mission Control observability stack** instead of SSH to fixed hosts.

This module assumes a Mission Control deployment (as in the [mc-lab](https://github.com/datastax/mc-lab) KinD environment). No diagnostic collector or Montecristo yet.

**Lab layout**

| Namespace | Contents |
|-----------|----------|
| `mission-control` | UI, operator, Mimir, Loki, Grafana, Vector, MinIO |
| `database` (or project namespace) | `MissionControlCluster`, Cassandra pods, Medusa, Reaper |

Adjust names to match your install.

---

## 1) Intended vs actual — CRs and Helm

Start with desired state:

```bash
kubectl get missioncontrolclusters -A
kubectl get cassandradatacenters,k8ssandraclusters -A
helm list -A | grep -i mission
```

For a specific cluster:

```bash
export NAMESPACE=database
export CLUSTER=two-dcs   # MissionControlCluster metadata.name

kubectl get missioncontrolcluster "${CLUSTER}" -n "${NAMESPACE}" -o yaml
kubectl describe missioncontrolcluster "${CLUSTER}" -n "${NAMESPACE}"
```

Look at **status conditions** and events — the operator surfaces reconciliation errors here before pods fail obviously.

---

## 2) Pod and workload health

```bash
kubectl get pods -n "${NAMESPACE}" -o wide --sort-by=.spec.nodeName
kubectl get statefulset -n "${NAMESPACE}"
kubectl get pvc -n "${NAMESPACE}"
```

| Symptom | Likely cause |
|---------|----------------|
| `CrashLoopBackOff` | Bad config, disk, heap, seed list |
| `Pending` | Scheduling, PVC, resources |
| `ImagePullBackOff` | Registry auth or wrong image |
| Ready **0/1** on Cassandra container | Startup, gossip, or probe failure |

Quick failure scan:

```bash
kubectl get pods -A | grep -E 'CrashLoop|Error|Pending|ImagePull'
kubectl get events -n "${NAMESPACE}" --sort-by=.lastTimestamp | tail -30
```

---

## 3) In-pod Cassandra checks — same nodetool, different path

Exec into a **Ready** seed or any UN pod:

```bash
POD=$(kubectl get pods -n "${NAMESPACE}" \
  -l cassandra.datastax.com/cluster="${CLUSTER}" \
  -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | awk '{print $1}')

kubectl exec -it "${POD}" -n "${NAMESPACE}" -c cassandra -- nodetool status
kubectl exec -it "${POD}" -n "${NAMESPACE}" -c cassandra -- nodetool tpstats
kubectl exec -it "${POD}" -n "${NAMESPACE}" -c cassandra -- nodetool compactionstats
```

Credentials for `cqlsh` usually live in a superuser secret:

```bash
kubectl get secret superuser -n "${NAMESPACE}" -o jsonpath='{.data.username}' | base64 -d; echo
```

**Kubernetes-specific checks**

- Pod **restart count** — `kubectl get pod -o custom-columns=NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount`
- **Liveness/readiness** failures in `kubectl describe pod`
- **PVC usage** — Prometheus/Grafana or `kubectl exec … df -h` on the data mount

---

## 4) Mission Control UI — control-plane and cluster view

Port-forward the UI:

```bash
kubectl port-forward svc/mission-control-ui -n mission-control 8080:8080
```

Open `https://localhost:8080`, select your project and cluster, then check:

| Area | What to verify |
|------|----------------|
| **Cluster overview** | All datacenters/racks shown, version, status |
| **Nodes** | Pod/node mapping, up/down, load |
| **Observability** | Metrics and logs flowing (not empty) |
| **Operations** | Recent backups, repairs, tasks |

Empty Observability often means telemetry pipeline issues — not necessarily database failure. Confirm observability pods next.

---

## 5) Observability pipeline — metrics and logs

Mission Control bundles Mimir (metrics), Loki (logs), and Vector (collection):

```bash
kubectl get pods -n mission-control | grep -E 'mimir|loki|aggregator|vector|grafana'
```

If charts are empty in UI or Grafana:

1. Database pods **Ready**
2. Vector aggregator **Running**
3. Mimir distributor / ingester **Running**
4. Allow a few minutes after install for first data points

Grafana (when enabled):

```bash
kubectl port-forward svc/mission-control-grafana -n mission-control 3000:80
```

Use bundled Cassandra/HCD dashboards for:

- Request latency and timeouts
- Compaction pending bytes
- JVM heap and GC
- Disk usage per pod

Ad-hoc investigation: **Explore** → Mimir or Loki.

---

## 6) Operator and platform health

```bash
kubectl get deploy -n mission-control | grep -E 'operator|ui|api'
kubectl logs -n mission-control deploy/mission-control-operator --tail=100
kubectl logs -n mission-control deploy/mission-control-k8ssandra-operator --tail=100
kubectl logs -n mission-control deploy/mission-control-ui --tail=50
```

Reconciliation loops, webhook failures, or certificate issues show up here before the data plane degrades.

---

## 7) Mapping K8s concepts to bare-metal mental model

| Bare metal | Kubernetes + Mission Control |
|------------|------------------------------|
| SSH to node | `kubectl exec` into Cassandra container |
| `systemctl status cassandra` | Pod phase, restart count, probes |
| `/var/lib/cassandra` on host | PVC + mount inside pod |
| Host metrics | Node exporter / cAdvisor → Mimir |
| `system.log` on disk | Loki log stream per pod |
| Rack / DC in `cassandra-rackdc.properties` | `MissionControlCluster` topology, affinity, labels |

---

## 8) Five-line health summary (K8s)

1. **CR status:** (`MissionControlCluster` / `CassandraDatacenter` conditions)
2. **Pods:** (N/M Ready, any CrashLoop or Pending)
3. **nodetool:** (all UN / down nodes)
4. **Observability:** (UI/Grafana populated or pipeline gap)
5. **Next step:** (fix pod, PVC, operator, or collect diagnostics)

Example:

> MCC Ready, 6/6 Cassandra pods Running. nodetool UN across DCs; tpstats clean. Grafana shows rising pending compaction on dc1 rack2 pod. Operator logs clean. Next: watch compaction metrics; schedule diagnostic collection if trend continues.

---

## Lab cross-reference

The [mc-lab observability guide](https://github.com/datastax/mc-lab/blob/main/docs/05-observability.md) walks through port-forwards, Grafana credentials, and pipeline troubleshooting on KinD.

➡️ **Next:** [Diagnostic collection](03-diagnostic-collection.md) — gather a support bundle from VM or K8s.
