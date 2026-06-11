# Montecristo analysis

[Montecristo](https://github.com/datastax-labs/Montecristo) turns diagnostic-collection tarballs into a structured **health discovery report**: infrastructure, configuration, compaction, repairs, schema notes, and prioritized recommendations.

This training uses a **Docker image** in this repository so you do not need Java 8, Hugo, Gradle, or a local [sperf](https://github.com/datastax-labs/sperf) install. The image runs **Montecristo** and **sperf** on the same collector tarballs.

---

## What Montecristo does

1. Decrypts artifacts (if `.enc` and key provided)
2. Extracts per-node tarballs
3. Builds a **metrics SQLite database** from `metrics.jmx` files
4. Runs discovery rules and generates Markdown sections
5. Runs **sperf** on the collector tarballs → `~/ds-discovery/<ISSUE_ID>/sperf/` ([details](06-sperf-analysis.md))
6. Serves an HTML report via **Hugo** (`/final/`)

Set `SKIP_SPERF=true` to skip step 5. Upstream `run.sh` also supports S3 download; the container workflow here uses **local artifacts only** (`-c`).

---

## Build the image

From this repository:

```bash
./scripts/analyze.sh build
```

Or directly:

```bash
docker build -t montecristo -f docker/Dockerfile docker/
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
| `ISSUE_ID` | Folder name under `~/ds-discovery` (e.g. ticket or cluster id) |
| `ARTIFACTS_DIR` | Host path with `*.tar.gz` / `*.enc` from ds-collector |
| `ENCRYPTION_KEY` | Optional `*_secret.key` for encrypted bundles |

### Example — plain tarballs

```bash
./scripts/analyze.sh run lab-2026-06 /tmp/datastax
```

This:

- Mounts `/tmp/datastax` read-only at `/artifacts`
- Writes results to `~/ds-discovery/lab-2026-06/`
- Starts Hugo on **http://localhost:1313/final/**

### Example — encrypted artifacts

```bash
./scripts/analyze.sh run lab-2026-06 /tmp/datastax /path/to/PROJECT_secret.key
```

### Example — manual `docker run`

```bash
docker run --rm \
  -v /tmp/datastax:/artifacts:ro \
  -v "$HOME/ds-discovery:/ds-discovery" \
  -p 1313:1313 \
  montecristo lab-2026-06 /artifacts
```

### Skip Hugo server (batch / CI)

```bash
SKIP_HUGO_SERVER=true ./scripts/analyze.sh run lab-2026-06 /tmp/datastax
```

View the report later:

```bash
cd ~/ds-discovery/lab-2026-06/reports/montecristo
hugo server
# open http://localhost:1313/final/
```

---

## Output layout

```
~/ds-discovery/<ISSUE_ID>/
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

## Limitations

| Topic | Note |
|-------|------|
| **DSE SSTable stats** | Rebuild image with `./scripts/analyze.sh build /path/to/dse-6.8.x-bin.tar.gz`; HCD/OSS paths work without |
| **C* 2.2** | Legacy stats converter prompt — answer **n** for modern clusters |
| **Multiple clusters** | One cluster name per run; split artifact directories |
| **Duplicate nodes** | Remove duplicate `*_artifacts_*` folders before run |
| **S3 pull** | Not used in this container; copy artifacts locally first |

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `PatternSyntaxException` / `Illegal repetition` during log parsing | Rebuild the image (`./scripts/analyze.sh build`) — patches modern `%date{"yyyy-MM-dd'T'HH:mm:ss,SSS", UTC}` logback patterns. |
| `N log entries were skipped, 0 entries were successfully parsed` | Same rebuild — `LogEntry` must parse `2026-06-10T12:48:39,008` timestamps (not only `yyyy-MM-dd HH:mm:ss`). |
| `No extracted artifacts found` / empty `/artifacts` | Run `ds-collector` first; confirm `ls /tmp/datastax/*.tar.gz` before `./scripts/analyze.sh run`. |
| Interactive `copy them from /artifacts` prompt | Answer **Y**, or use `-y` for non-interactive: `./run.sh -y -g -c /artifacts/ ISSUE_ID` |
| `More than 1 cluster name detected` | Separate collections per cluster |
| `Duplicate entries found for the following nodes` | Keep newest tarball per hostname |
| `Encrypted artifacts … no encryption key` | Pass key file as third argument |
| Hugo port in use | `-p 1314:1313` or `SKIP_HUGO_SERVER=true` |
| Build fails on Java | Image uses `openjdk-8-jdk`; rebuild with `--no-cache` |
| Gradle `Premature end of Content-Length` during `docker build` | Transient download corruption; re-run `./scripts/analyze.sh build` (image retries up to 5 times) or `docker build --no-cache …` |

Upstream references: [Montecristo README](https://github.com/datastax-labs/Montecristo), [BUILD.md](https://github.com/datastax-labs/Montecristo/blob/main/BUILD.md).

---

## Training exercise

1. Complete a [bare-metal](01-health-snapshot-bare-metal.md) or [K8s](02-health-snapshot-kubernetes.md) snapshot on a lab cluster.
2. Run [diagnostic collection](03-diagnostic-collection.md) with `skipS3=true`.
3. Analyze with `./scripts/analyze.sh run training-1 /tmp/datastax`.
4. List three findings from the Montecristo summary that your snapshot did **not** surface.
5. List one finding from your snapshot that Montecristo **under-emphasized** — explain why live triage still matters.
