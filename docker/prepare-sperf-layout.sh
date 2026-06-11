#!/usr/bin/env bash
# Stage ds-collector tarballs for sperf. OUT_DIR must contain only nodes/ (sperf walks all of -d).
set -euo pipefail

ARTIFACTS_DIR="${1:?artifacts directory required}"
OUT_DIR="${2:?nodes output directory required}"
STAGE_DIR="${3:?extract staging directory required}"

mkdir -p "${OUT_DIR}" "${STAGE_DIR}"

link_node() {
  local artifact_dir="$1"
  local node_dir node_name

  if [[ -f "${artifact_dir}/os/hostname.txt" ]]; then
    node_name="$(tr -d '[:space:]' < "${artifact_dir}/os/hostname.txt")"
  else
    node_name="$(basename "${artifact_dir}" | sed 's/_artifacts_.*//')"
  fi

  node_dir="${OUT_DIR}/nodes/${node_name}"
  mkdir -p "${node_dir}"

  link_if_present() {
    local src="$1"
    local dest_name="$2"
    if [[ -e "${src}" ]]; then
      ln -sf "${src}" "${node_dir}/${dest_name}"
    fi
  }

  link_if_present "${artifact_dir}/logs/system.log" "system.log"
  link_if_present "${artifact_dir}/logs/debug.log" "debug.log"
  link_if_present "${artifact_dir}/logs/gc.log" "gc.log"
  link_if_present "${artifact_dir}/nodetool/cfstats.txt" "cfstats.txt"
  link_if_present "${artifact_dir}/os/blockdev-report.txt" "blockdev_report.txt"
  link_if_present "${artifact_dir}/conf/jvm.options" "jvm.options"
}

collect_from_dir() {
  local parent="$1"
  local found=0
  shopt -s nullglob
  for artifact_dir in "${parent}"/*_artifacts_*; do
    if [[ -d "${artifact_dir}" ]]; then
      link_node "${artifact_dir}"
      found=1
    fi
  done
  shopt -u nullglob
  return $((1 - found))
}

extract_tarballs() {
  shopt -s nullglob
  local tarball
  for tarball in "${ARTIFACTS_DIR}"/*.tar.gz; do
    # Full extract; ignore device nodes and /proc entries that fail on some hosts.
    tar -xzf "${tarball}" -C "${STAGE_DIR}" \
      --exclude='*/proc/*' \
      --exclude='*/os/interrupts' \
      2>/dev/null \
      || tar -xzf "${tarball}" -C "${STAGE_DIR}" 2>/dev/null \
      || true
  done
  shopt -u nullglob
}

if [[ -d "${ARTIFACTS_DIR}/extracted" ]] && collect_from_dir "${ARTIFACTS_DIR}/extracted"; then
  :
elif collect_from_dir "${ARTIFACTS_DIR}"; then
  :
else
  extract_tarballs
  if ! collect_from_dir "${STAGE_DIR}"; then
    echo "No ds-collector artifacts found in ${ARTIFACTS_DIR}" >&2
    exit 1
  fi
fi

if [[ ! -d "${OUT_DIR}/nodes" ]] || [[ -z "$(ls -A "${OUT_DIR}/nodes" 2>/dev/null)" ]]; then
  echo "sperf staging produced no nodes under ${OUT_DIR}/nodes" >&2
  exit 1
fi

echo "${OUT_DIR}"
