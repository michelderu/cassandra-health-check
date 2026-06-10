#!/usr/bin/env bash
# Build Montecristo inside the image; retry on flaky Gradle dependency downloads.
set -euo pipefail

DEST="${1:-/opt/montecristo}"
DSE_TARBALL="${2:-}"
if [[ -n "${DSE_TARBALL}" && ! -f "${DSE_TARBALL}" ]]; then
  echo "DSE tarball not found (skipping -d): ${DSE_TARBALL}" >&2
  DSE_TARBALL=""
fi
MAX_ATTEMPTS="${BUILD_MAX_ATTEMPTS:-5}"

export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.daemon=false -Dorg.gradle.parallel=false"

# Longer timeouts for slow or interrupted downloads inside Docker builds.
mkdir -p /root/.gradle
cat >> /root/.gradle/gradle.properties <<'EOF'
systemProp.org.gradle.internal.http.connectionTimeout=120000
systemProp.org.gradle.internal.http.socketTimeout=120000
org.gradle.jvmargs=-Xmx2g
EOF

attempt=1
while [[ "${attempt}" -le "${MAX_ATTEMPTS}" ]]; do
  echo "Montecristo build attempt ${attempt}/${MAX_ATTEMPTS}..."
  build_args=()
  if [[ -n "${DSE_TARBALL}" ]]; then
    echo "Including DSE jars from ${DSE_TARBALL}"
    build_args+=(-d "${DSE_TARBALL}")
  fi
  build_args+=("${DEST}")
  if ./build.sh "${build_args[@]}"; then
    echo "Montecristo build succeeded on attempt ${attempt}."
    exit 0
  fi

  echo "Build failed on attempt ${attempt}; clearing partial Gradle caches before retry."
  rm -rf /root/.gradle/caches/modules-2/files-2.1/com.github.jengelman.gradle.plugins \
         /root/.gradle/caches/modules-2/metadata-2.*/descriptors/com.github.jengelman.gradle.plugins \
         montecristo/.gradle \
         montecristo/build \
         dse-stats-converter/.gradle \
         dse-stats-converter/build \
         old-c-stats-converter/.gradle \
         old-c-stats-converter/build 2>/dev/null || true

  attempt=$((attempt + 1))
  sleep $((attempt * 3))
done

echo "Montecristo build failed after ${MAX_ATTEMPTS} attempts." >&2
exit 1
