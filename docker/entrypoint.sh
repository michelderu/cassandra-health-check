#!/usr/bin/env bash
# Run Montecristo (+ sperf) on diagnostic-collection artifacts.
set -euo pipefail

MONTECRISTO_SRC=/opt/montecristo-src
DS_DISCOVERY_DIR="${DS_DISCOVERY_DIR:-/ds-discovery}"

usage() {
  cat <<'EOF'
Analysis container — Montecristo report + sperf CLI summaries.

Usage:
  entrypoint.sh <ISSUE_ID> <ARTIFACTS_DIR> [ENCRYPTION_KEY_FILE]
  entrypoint.sh sperf <ISSUE_ID> <ARTIFACTS_DIR>
  entrypoint.sh --help

Modes:
  default   Montecristo on *.tar.gz, then sperf, then Hugo (unless skipped).
  sperf     sperf only — reads ds-collector tarballs from ARTIFACTS_DIR.

Arguments:
  ISSUE_ID            Folder name under DS_DISCOVERY_DIR.
  ARTIFACTS_DIR       Directory with *.tar.gz from ds-collector.
  ENCRYPTION_KEY_FILE Optional *_secret.key for encrypted artifacts.

Environment:
  DS_DISCOVERY_DIR    Working directory (default: /ds-discovery).
  SKIP_SPERF          Set "true" to skip sperf in default mode.
  SKIP_HUGO_SERVER    Set "true" to skip Hugo.
  HUGO_BIND / HUGO_PORT

Examples:
  docker run --rm -v "$(pwd)/diagnostics:/artifacts:ro" -v "$(pwd)/ds-discovery:/ds-discovery" -p 1313:1313 \
    montecristo docker-lab /artifacts

  docker run --rm -v "$(pwd)/diagnostics:/artifacts:ro" -v "$(pwd)/ds-discovery:/ds-discovery" \
    montecristo sperf docker-lab /artifacts
EOF
}

run_sperf_reports() {
  local base="$1"
  local artifacts_dir="$2"
  local extracted_dir="${3:-}"
  local sperf_out="${base}/sperf"

  echo ""
  echo "Running sperf on collector tarballs..."
  /usr/local/bin/run-sperf.sh "${artifacts_dir}" "${sperf_out}" "${extracted_dir}"
}

run_montecristo() {
  local issue_id="$1"
  local artifacts_dir="$2"
  local encryption_key="${3:-}"

  mkdir -p "${DS_DISCOVERY_DIR}/${issue_id}"
  cd "${MONTECRISTO_SRC}"

  local run_args=(-y -s -c "${artifacts_dir}" "${issue_id}")
  if [[ -n "${encryption_key}" ]]; then
    run_args+=("${encryption_key}")
  fi
  ./run.sh "${run_args[@]}"
}

start_hugo() {
  local base="$1"
  local report_dir="${base}/reports/montecristo"

  if [[ "${SKIP_HUGO_SERVER:-false}" == "true" ]]; then
    echo "  View report  : cd ${report_dir} && hugo server"
    return 0
  fi
  if [[ ! -d "${report_dir}" ]]; then
    echo "Report directory missing; skipping Hugo." >&2
    return 0
  fi

  local hugo_bind="${HUGO_BIND:-0.0.0.0}"
  local hugo_port="${HUGO_PORT:-1313}"
  echo "  Hugo server  : http://localhost:${hugo_port}/final/"
  echo ""
  cd "${report_dir}"
  exec hugo server --bind "${hugo_bind}" --port "${hugo_port}" --baseURL "http://localhost:${hugo_port}/"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 1
fi

MODE="montecristo"
if [[ "${1:-}" == "sperf" ]]; then
  MODE="sperf"
  shift
fi

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 1
fi

ISSUE_ID="$1"
ARTIFACTS_DIR="$2"
ENCRYPTION_KEY="${3:-}"

if [[ ! -d "${ARTIFACTS_DIR}" ]]; then
  echo "Artifacts directory not found: ${ARTIFACTS_DIR}" >&2
  exit 1
fi

if [[ -n "${ENCRYPTION_KEY}" && ! -f "${ENCRYPTION_KEY}" ]]; then
  echo "Encryption key file not found: ${ENCRYPTION_KEY}" >&2
  exit 1
fi

BASE="${DS_DISCOVERY_DIR}/${ISSUE_ID}"
mkdir -p "${BASE}"

if [[ "${MODE}" == "sperf" ]]; then
  run_sperf_reports "${BASE}" "${ARTIFACTS_DIR}"
  echo ""
  echo "sperf complete. Output: ${BASE}/sperf/"
  exit 0
fi

run_montecristo "${ISSUE_ID}" "${ARTIFACTS_DIR}" "${ENCRYPTION_KEY}"

REPORT_DIR="${BASE}/reports/montecristo"
EXTRACTED="${BASE}/extracted"

echo ""
echo "Montecristo analysis complete."
echo "  Issue folder : ${BASE}"
echo "  Metrics DB   : ${BASE}/metrics.db"
echo "  Report       : ${REPORT_DIR}"

if [[ "${SKIP_SPERF:-false}" != "true" ]]; then
  run_sperf_reports "${BASE}" "${ARTIFACTS_DIR}" "${EXTRACTED}"
  echo "  sperf output : ${BASE}/sperf/"
fi

start_hugo "${BASE}"
