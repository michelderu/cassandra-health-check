#!/usr/bin/env bash
# Run sperf on ds-collector tarballs (staged to legacy nodes/ layout inside the container).
set -euo pipefail

ARTIFACTS_DIR="${1:?artifacts directory required}"
OUT_DIR="${2:?report output directory required}"
EXTRACTED_DIR="${3:-}"

if ! command -v sperf >/dev/null 2>&1; then
  echo "sperf not found in PATH" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

SPERF_ROOT="$(mktemp -d)"
SPERF_INPUT="${SPERF_ROOT}/diag"
STAGE_DIR="${SPERF_ROOT}/stage"
mkdir -p "${SPERF_INPUT}" "${STAGE_DIR}"
CLEANUP_ROOT=1

cleanup() {
  if [[ "${CLEANUP_ROOT}" -eq 1 ]]; then
    rm -rf "${SPERF_ROOT}"
  fi
}
trap cleanup EXIT

layout_source="${ARTIFACTS_DIR}"
if [[ -n "${EXTRACTED_DIR}" && -d "${EXTRACTED_DIR}" ]]; then
  layout_source="${EXTRACTED_DIR}"
fi

/usr/local/bin/prepare-sperf-layout.sh "${layout_source}" "${SPERF_INPUT}" "${STAGE_DIR}" >/dev/null

echo "sperf input (nodes/): ${SPERF_INPUT}"
echo "sperf reports: ${OUT_DIR}"
ls -1 "${SPERF_INPUT}/nodes/" | sed 's/^/  node: /' || true
python3 -c "from pysper import VERSION; print('sperf', VERSION)" 2>/dev/null | tee "${OUT_DIR}/version.txt" || true

run_sperf_top() {
  local name="$1"
  local outfile="${OUT_DIR}/${name}.txt"
  echo ""
  echo "==> sperf -d ${SPERF_INPUT}"
  if sperf -d "${SPERF_INPUT}" | tee "${outfile}"; then
    return 0
  fi
  echo "warning: sperf summary failed (see ${outfile})" >&2
  return 0
}

run_sperf_core() {
  local name="$1"
  shift
  local outfile="${OUT_DIR}/${name}.txt"
  echo ""
  echo "==> sperf $* -d ${SPERF_INPUT}"
  if sperf "$@" -d "${SPERF_INPUT}" | tee "${outfile}"; then
    return 0
  fi
  echo "warning: sperf $* failed (see ${outfile})" >&2
  return 0
}

run_sperf_top summary
run_sperf_core core-gc core gc
run_sperf_core core-statuslogger core statuslogger
run_sperf_core core-diag core diag

echo ""
echo "sperf reports written under ${OUT_DIR}"
