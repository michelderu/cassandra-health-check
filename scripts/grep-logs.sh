#!/usr/bin/env bash
# Quick ERROR/WARN/GC grep over collector artifacts (tarballs or already extracted).
set -euo pipefail

usage() {
  cat <<'EOF'
Grep Cassandra system.log files from diagnostic-collection artifacts.

Usage:
  ./scripts/grep-logs.sh <ARTIFACTS_DIR> [OUTPUT_DIR]

Arguments:
  ARTIFACTS_DIR  Directory with *.tar.gz from ds-collector, or an already-extracted tree.
  OUTPUT_DIR     Where to write errors.log, warnings.log, etc.
                 (default: <ARTIFACTS_DIR>/log-grep)

If ARTIFACTS_DIR contains tarballs and Montecristo has not run yet, each *.tar.gz is
extracted under <OUTPUT_DIR>/extracted/ before grepping.

Examples:
  ./scripts/grep-logs.sh /tmp/datastax
  ./scripts/grep-logs.sh /tmp/datastax /tmp/log-triage
  ./scripts/grep-logs.sh ~/ds-discovery/docker-lab/extracted
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

artifacts_dir="$(cd "$1" && pwd)"
if [[ $# -ge 2 ]]; then
  output_dir="$(mkdir -p "$2" && cd "$2" && pwd)"
else
  output_dir="$(mkdir -p "${artifacts_dir}/log-grep" && cd "${artifacts_dir}/log-grep" && pwd)"
fi

extracted_dir=""
auto_extracted=0

if find "${artifacts_dir}" -name 'system.log*' -print -quit 2>/dev/null | grep -q .; then
  extracted_dir="${artifacts_dir}"
elif compgen -G "${artifacts_dir}"/*.tar.gz > /dev/null; then
  extracted_dir="${output_dir}/extracted"
  mkdir -p "${extracted_dir}"
  auto_extracted=1
  for tarball in "${artifacts_dir}"/*.tar.gz; do
    echo "Extracting logs from $(basename "${tarball}")..."
    # Logs only — full tar -x can fail on collected /proc or device nodes.
    tar -tzf "${tarball}" | grep -E '/logs/.+' \
      | tar -xzf "${tarball}" -C "${extracted_dir}" -T -
  done
else
  echo "No system.log files or *.tar.gz under ${artifacts_dir}" >&2
  exit 1
fi

if ! find "${extracted_dir}" -name 'system.log*' -print -quit 2>/dev/null | grep -q .; then
  echo "No system.log files found after extraction under ${extracted_dir}" >&2
  exit 1
fi

run_grep() {
  local pattern="$1"
  local outfile="$2"
  shift 2
  find "${extracted_dir}" -name 'system.log*' -print0 \
    | xargs -0 grep -Ee "${pattern}" 2>/dev/null \
    | grep "$@" \
    > "${outfile}" || true
  wc -l < "${outfile}" | xargs -I{} echo "  ${outfile}: {} lines"
}

echo "Scanning ${extracted_dir}"
if [[ "${auto_extracted}" -eq 1 ]]; then
  echo "(extracted from tarballs in ${artifacts_dir})"
fi
echo "Writing to ${output_dir}"
echo

run_grep 'ERROR' "${output_dir}/errors.log" -v 'tombstone cells for query'
run_grep 'WARN' "${output_dir}/warnings.log" -v 'tombstone cells for query'
run_grep 'gc' "${output_dir}/gc-from-system.log" -v 'tombstone cells for query'
run_grep 'ERROR|WARN' "${output_dir}/errors-tombstones.log" 'tombstone cells for query'

if find "${extracted_dir}" -path '*/logs/gc.log' -print -quit 2>/dev/null | grep -q .; then
  find "${extracted_dir}" -path '*/logs/gc.log' -print0 \
    | xargs -0 cat > "${output_dir}/gc.log" 2>/dev/null || true
  wc -l < "${output_dir}/gc.log" | xargs -I{} echo "  ${output_dir}/gc.log: {} lines (from logs/gc.log)"
fi

echo
echo "Done."
