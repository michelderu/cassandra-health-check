#!/usr/bin/env bash
# Build and run the Montecristo analysis container.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_NAME="${MONTECRISTO_IMAGE:-montecristo}"
DISCOVERY_DIR="${DS_DISCOVERY_DIR:-${HOME}/ds-discovery}"

usage() {
  cat <<'EOF'
Analyze diagnostic-collection artifacts with Montecristo (Docker).

Usage:
  ./scripts/analyze.sh build [DSE_TARBALL]
  ./scripts/analyze.sh run <ISSUE_ID> <ARTIFACTS_DIR> [ENCRYPTION_KEY_FILE]

Environment:
  MONTECRISTO_IMAGE   Docker image name (default: montecristo)
  DSE_TARBALL         DSE binary tarball for optional SSTable stats (build only)
  DS_DISCOVERY_DIR    Host mount for analysis output (default: ~/ds-discovery)
  SKIP_HUGO_SERVER    Pass through to container (true|false)
EOF
}

cmd="${1:-}"
shift || true

case "${cmd}" in
  build)
    dse_tarball="${DSE_TARBALL:-${1:-}}"
    optional_dir="${REPO_ROOT}/docker/optional"
    staged_dse="${optional_dir}/dse-bin.tar.gz"
    cleanup_dse=0
    if [[ -n "${dse_tarball}" ]]; then
      if [[ ! -f "${dse_tarball}" ]]; then
        echo "DSE tarball not found: ${dse_tarball}" >&2
        exit 1
      fi
      cp -f "${dse_tarball}" "${staged_dse}"
      cleanup_dse=1
      echo "Building with DSE SSTable stats jars from ${dse_tarball}"
    fi
    docker build -t "${IMAGE_NAME}" -f "${REPO_ROOT}/docker/Dockerfile" "${REPO_ROOT}/docker"
    if [[ "${cleanup_dse}" -eq 1 ]]; then
      rm -f "${staged_dse}"
    fi
    ;;
  run)
    if [[ $# -lt 2 ]]; then
      usage >&2
      exit 1
    fi
    issue_id="$1"
    artifacts_dir="$(cd "$2" && pwd)"
    key_file="${3:-}"
    mkdir -p "${DISCOVERY_DIR}"

    docker_args=(
      --rm
      -v "${artifacts_dir}:/artifacts:ro"
      -v "${DISCOVERY_DIR}:/ds-discovery"
      -p 1313:1313
    )
    if [[ -n "${key_file}" ]]; then
      key_dir="$(cd "$(dirname "${key_file}")" && pwd)"
      key_base="$(basename "${key_file}")"
      docker_args+=(-v "${key_dir}:/key:ro")
      run_args=("${issue_id}" /artifacts "/key/${key_base}")
    else
      run_args=("${issue_id}" /artifacts)
    fi
    if [[ -n "${SKIP_HUGO_SERVER:-}" ]]; then
      docker_args+=(-e "SKIP_HUGO_SERVER=${SKIP_HUGO_SERVER}")
    fi

    docker run "${docker_args[@]}" "${IMAGE_NAME}" "${run_args[@]}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
