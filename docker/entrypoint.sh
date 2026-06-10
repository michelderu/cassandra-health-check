#!/usr/bin/env bash
# Run Montecristo analysis on local diagnostic-collection artifacts (non-interactive).
set -euo pipefail

MONTECRISTO_SRC=/opt/montecristo-src
MONTECRISTO_BIN=/opt/montecristo/montecristo/bin/montecristo
DS_DISCOVERY_DIR="${DS_DISCOVERY_DIR:-/ds-discovery}"

usage() {
  cat <<'EOF'
Montecristo container — analyze diagnostic-collection tarballs.

Usage:
  entrypoint.sh <ISSUE_ID> <ARTIFACTS_DIR> [ENCRYPTION_KEY_FILE]
  entrypoint.sh --help

Arguments:
  ISSUE_ID            Folder name under DS_DISCOVERY_DIR (e.g. ticket or cluster id).
  ARTIFACTS_DIR       Directory with *.tar.gz and/or *.enc files from ds-collector.
  ENCRYPTION_KEY_FILE Optional path to *_secret.key when artifacts are encrypted.

Environment:
  DS_DISCOVERY_DIR    Working directory (default: /ds-discovery).
  SKIP_HUGO_SERVER    Set to "true" to skip the Hugo report server (default: false).
  HUGO_BIND           Hugo bind address (default: 0.0.0.0).
  HUGO_PORT           Hugo port (default: 1313).

Examples:
  docker run --rm \
    -v /tmp/collector-output:/artifacts:ro \
    -v "$HOME/ds-discovery:/ds-discovery" \
    -p 1313:1313 \
    montecristo lab-2026-06 /artifacts

  docker run --rm \
    -v /tmp/collector-output:/artifacts:ro \
    -v /tmp/key:/key:ro \
    -v "$HOME/ds-discovery:/ds-discovery" \
    -p 1313:1313 \
    montecristo lab-2026-06 /artifacts /key/PROJECT_secret.key
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
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

mkdir -p "${DS_DISCOVERY_DIR}/${ISSUE_ID}"

cd "${MONTECRISTO_SRC}"

RUN_ARGS=(-y -s -c "${ARTIFACTS_DIR}" "${ISSUE_ID}")
if [[ -n "${ENCRYPTION_KEY}" ]]; then
  RUN_ARGS+=("${ENCRYPTION_KEY}")
fi

# -s: skip Hugo in run.sh; this entrypoint serves the report when enabled.
./run.sh "${RUN_ARGS[@]}"

BASE="${DS_DISCOVERY_DIR}/${ISSUE_ID}"
REPORT_DIR="${BASE}/reports/montecristo"

echo ""
echo "Analysis complete."
echo "  Issue folder : ${BASE}"
echo "  Metrics DB   : ${BASE}/metrics.db"
echo "  Report       : ${REPORT_DIR}"

if [[ "${SKIP_HUGO_SERVER:-false}" == "true" ]]; then
  echo "  View report  : cd ${REPORT_DIR} && hugo server"
  exit 0
fi

if [[ ! -d "${REPORT_DIR}" ]]; then
  echo "Report directory missing; skipping Hugo server." >&2
  exit 0
fi

HUGO_BIND="${HUGO_BIND:-0.0.0.0}"
HUGO_PORT="${HUGO_PORT:-1313}"

echo "  Hugo server  : http://localhost:${HUGO_PORT}/final/"
echo ""

cd "${REPORT_DIR}"
exec hugo server --bind "${HUGO_BIND}" --port "${HUGO_PORT}" --baseURL "http://localhost:${HUGO_PORT}/"
