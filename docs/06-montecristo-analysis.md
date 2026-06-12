# Montecristo analysis

[Montecristo](https://github.com/datastax-labs/Montecristo) turns diagnostic-collection tarballs into a structured **health discovery report**: infrastructure, configuration, compaction, repairs, schema notes, and prioritized recommendations.

This training uses a **Docker image** in this repository so you do not need Java 8, Hugo, Gradle, or a local [sperf](https://github.com/datastax-labs/sperf) install. The image runs **Montecristo** and **sperf** on the same collector tarballs.

---

## What Montecristo does

1. Decrypts artifacts (if `.enc` and key provided)
2. Extracts per-node tarballs
3. Builds a **metrics SQLite database** from `metrics.jmx` files
4. Runs discovery rules and generates Markdown sections
5. Runs **sperf** on the collector tarballs → `./ds-discovery/<ISSUE_ID>/sperf/` ([details](05-sperf-analysis.md))
6. Serves an HTML report via **Hugo** (`/final/`)

Set `SKIP_SPERF=true` to skip step 5. Upstream `run.sh` also supports S3 download; the container workflow here uses **local artifacts only** (`-c`).

---

## Build the image

From this repository, if not previously already done so:

```bash
./scripts/analyze.sh build
```

The image clones Montecristo from GitHub and runs `build.sh` at image build time (Java 8, Gradle wrapper, Hugo theme zip).

Optional: pin a release branch at build time:

```bash
docker build --build-arg MONTECRISTO_REF=main -t montecristo -f docker/Dockerfile docker/
```

Optional: include DSE SSTable statistics conversion ([Montecristo README step 6](https://github.com/datastax-labs/Montecristo/tree/main)). Download a DSE binary tarball from IBM Fix Central (e.g. `dse-6.8.x-bin.tar.gz`) and pass it at build time:

```bash
./scripts/analyze.sh build /path/to/dse-6.8.x-bin.tar.gz
```

Or with an environment variable:

```bash
DSE_TARBALL=/path/to/dse-6.8.x-bin.tar.gz ./scripts/analyze.sh build
```

The build runs `./build.sh -d` to extract proprietary jars into `dse-stats-converter/libs/`. Not required for OSS Cassandra or HCD lab collections; use when analyzing diagnostics from DSE clusters.

---

## Run analysis

### Inputs

| Argument | Description |
|----------|-------------|
| `ISSUE_ID` | Folder name under `./ds-discovery/` (e.g. ticket or cluster id) |
| `ARTIFACTS_DIR` | Host path with `*.tar.gz` / `*.enc` from ds-collector |
| `ENCRYPTION_KEY` | Optional `*_secret.key` for encrypted bundles |

### Example — plain tarballs

```bash
./scripts/analyze.sh run docker-lab ./diagnostics
```

This:

- Mounts `./diagnostics` read-only at `/artifacts`
- Writes results to `./ds-discovery/docker-lab/`
- Starts Hugo on **http://localhost:1313/final/**

### Example — encrypted artifacts

```bash
./scripts/analyze.sh run docker-lab ./diagnostics /path/to/PROJECT_secret.key
```

### Example — manual `docker run`

```bash
docker run --rm \
  -v "$(pwd)/diagnostics:/artifacts:ro" \
  -v "$(pwd)/ds-discovery:/ds-discovery" \
  -p 1313:1313 \
  montecristo docker-lab /artifacts
```

### Skip Hugo server (batch / CI)

```bash
SKIP_HUGO_SERVER=true ./scripts/analyze.sh run docker-lab ./diagnostics
```

View the report later:

```bash
cd ./ds-discovery/docker-lab/reports/montecristo
hugo server
# open http://localhost:1313/final/
```

---

## Output layout

```
./ds-discovery/<ISSUE_ID>/
├── artifacts/          # copied tarballs (optional)
├── extracted/          # per-node extracted trees
├── metrics.db          # JMX metrics database
├── reports/
│   └── montecristo/    # Hugo site — open /final/
└── issue.txt
```

Key report sections (numbered Markdown under `reports/montecristo/content/`):

- Summary and recommendations
- Infrastructure (OS, disk, NTP, Java)
- Configuration (version, custom settings)
- Operations (compaction, repairs, GC)
- Schema and table statistics (where data exists)

---

## Reading the report

1. Open **Summary** first — ranked findings and severity.
2. Cross-check against your [health snapshot](01-health-snapshot-bare-metal.md) or [K8s snapshot](02-health-snapshot-kubernetes.md) — Montecristo may flag config drift you already suspected.
3. Rule out environment-specific false positives (e.g. KinD resource limits vs production sizing).
4. Export: copy from browser or use generated Markdown for your runbook.

Re-run analysis after Montecristo upgrades without re-extracting:

```bash
# Inside upstream clone (not required for Docker users on fresh runs)
./run.sh -e -y <ISSUE_ID>
```

---

## Related

Upstream references: [Montecristo README](https://github.com/datastax-labs/Montecristo), [BUILD.md](https://github.com/datastax-labs/Montecristo/blob/main/BUILD.md).