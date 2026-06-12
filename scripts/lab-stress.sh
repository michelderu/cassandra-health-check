#!/usr/bin/env bash
# Load sample data via cassandra-stress on the lab Cassandra container.
# Start the container first — see docs/03-local-lab.md.
set -euo pipefail

CONTAINER="${LAB_CONTAINER:-ds-collector-test-cassandra}"
KEYSPACE="${LAB_KEYSPACE:-lab_stress}"
ROWS="${LAB_ROWS:-100000}"
READS="${LAB_READS:-100000}"
THREADS="${LAB_THREADS:-4}"

STRESS_BIN="/opt/cassandra/tools/bin/cassandra-stress"
CQLSH="cqlsh localhost 9042"

usage() {
  cat <<EOF
Generate CQL load on the lab Cassandra container (cassandra-stress).

Prerequisites (docs/03-local-lab.md):
  docker compose -f docker/docker-compose.cassandra.yml up -d
  # wait until: docker exec ds-collector-test-cassandra nodetool status shows UN

Usage:
  ./scripts/lab-stress.sh [command]

Commands:
  all       Write + read stress, then nodetool verify (default)
  write     cassandra-stress write only
  read      cassandra-stress read only (keyspace must exist)
  schema    Create keyspace via cqlsh (no stress)
  verify    nodetool tablestats / tpstats / compactionstats
  help      This message

Environment:
  LAB_CONTAINER   Docker container name (default: ds-collector-test-cassandra)
  LAB_KEYSPACE    Keyspace name (default: lab_stress; stress creates standard1)
  LAB_ROWS        Write row count (default: 100000)
  LAB_READS       Read op count for read phase (default: 100000)
  LAB_THREADS     Stress threads (default: 4)

Example:
  ./scripts/lab-stress.sh
  LAB_ROWS=200000 ./scripts/lab-stress.sh write
  ./scripts/lab-stress.sh verify
EOF
}

need_container() {
  if ! docker inspect "${CONTAINER}" >/dev/null 2>&1; then
    echo "Container not found: ${CONTAINER}" >&2
    echo "Start it: docker compose -f docker/docker-compose.cassandra.yml up -d" >&2
    exit 1
  fi
}

node_is_un() {
  local status
  status="$(docker exec "${CONTAINER}" nodetool status 2>&1)" || status=""
  # Match the status column (avoid pipefail: nodetool may exit non-zero while still printing output).
  grep -qE '(^|[[:space:]])UN[[:space:]]' <<<"${status}" && return 0
  # Compose healthcheck uses the same nodetool probe — accept it when present.
  local health
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "${CONTAINER}" 2>/dev/null || true)"
  [[ "${health}" == "healthy" ]]
}

require_un() {
  need_container
  if ! docker exec "${CONTAINER}" nodetool status 2>/dev/null | grep -q '^UN'; then
    if ! node_is_un; then
      echo "Node is not UN yet." >&2
      echo "Wait until UN: docker exec ${CONTAINER} nodetool status" >&2
      exit 1
    fi
  fi
}

exec_in() {
  docker exec "${CONTAINER}" "$@"
}

run_schema() {
  echo "Creating keyspace ${KEYSPACE} (if needed)..."
  exec_in ${CQLSH} -e "
CREATE KEYSPACE IF NOT EXISTS ${KEYSPACE}
  WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};
"
}

run_write() {
  echo "cassandra-stress write: ${ROWS} rows, ${THREADS} threads, keyspace=${KEYSPACE}"
  exec_in "${STRESS_BIN}" write "n=${ROWS}" cl=ONE \
    -rate "threads=${THREADS}" \
    -node localhost \
    -schema "keyspace=${KEYSPACE}" "replication(strategy=SimpleStrategy,factor=1)" \
    -pop "seq=1..${ROWS}"
}

run_read() {
  echo "cassandra-stress read: ${READS} ops, ${THREADS} threads, keyspace=${KEYSPACE}"
  exec_in "${STRESS_BIN}" read "n=${READS}" cl=ONE \
    -rate "threads=${THREADS}" \
    -node localhost \
    -schema "keyspace=${KEYSPACE}" "replication(strategy=SimpleStrategy,factor=1)" \
    -pop "seq=1..${ROWS}"
}

run_verify() {
  echo "=== nodetool tablestats ${KEYSPACE} ==="
  exec_in nodetool tablestats "${KEYSPACE}" 2>/dev/null || exec_in nodetool tablestats
  echo ""
  echo "=== nodetool tpstats (first 20 lines) ==="
  exec_in nodetool tpstats | head -20 || true
  echo ""
  echo "=== nodetool compactionstats ==="
  exec_in nodetool compactionstats
}

cmd="${1:-all}"

case "${cmd}" in
  help|-h|--help)
    usage
    ;;
  verify|status)
    require_un
    run_verify
    ;;
  schema)
    require_un
    run_schema
    ;;
  write)
    require_un
    run_write
    ;;
  read)
    require_un
    run_read
    ;;
  all)
    require_un
    run_write
    run_read
    run_verify
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    usage >&2
    exit 1
    ;;
esac
