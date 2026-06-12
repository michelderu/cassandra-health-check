# Montecristo + sperf analysis container for Cassandra / HCD / DSE diagnostic tarballs.
# Builds Montecristo from source; bundles sperf for CLI summaries on ds-collector bundles.
#
# Usage:
#   docker build -t montecristo -f docker/Dockerfile docker/
#   # Optional DSE SSTable stats support (Montecristo README step 6):
#   cp /path/to/dse-6.8.x-bin.tar.gz docker/optional/dse-bin.tar.gz
#   docker build -t montecristo -f docker/Dockerfile docker/
#   docker run --rm -v /path/to/collector-output:/artifacts:ro \
#     -v "$(pwd)/ds-discovery:/ds-discovery" -p 1313:1313 \
#     montecristo lab-run /artifacts

FROM ubuntu:22.04

ARG MONTECRISTO_REF=main
ARG SPERF_REF=v0.6.20
ENV DEBIAN_FRONTEND=noninteractive \
    DS_DISCOVERY_DIR=/ds-discovery \
    JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    hugo \
    jq \
    openjdk-8-jdk \
    openssl \
    python3 \
    python3-pip \
    tar \
    unzip \
    zip \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir "git+https://github.com/datastax-labs/sperf.git@${SPERF_REF}"

WORKDIR /opt/montecristo-src

# Clone separately so source layer is cached when only the build script changes.
RUN git clone --depth 1 --branch "${MONTECRISTO_REF}" \
    https://github.com/datastax-labs/Montecristo.git .

COPY build-montecristo.sh /tmp/build-montecristo.sh
COPY patch-logregex.sh /tmp/patch-logregex.sh
COPY optional/ /tmp/optional/
RUN chmod +x /tmp/build-montecristo.sh /tmp/patch-logregex.sh \
    && /tmp/patch-logregex.sh /opt/montecristo-src \
    && DSE_TARBALL="" \
    && if [ -f /tmp/optional/dse-bin.tar.gz ]; then DSE_TARBALL=/tmp/optional/dse-bin.tar.gz; fi \
    && /tmp/build-montecristo.sh /opt/montecristo "${DSE_TARBALL}" \
    && mkdir -p /opt/montecristo-src/build/install \
    && ln -sfn /opt/montecristo/montecristo /opt/montecristo-src/build/install/montecristo \
    && ln -sfn /opt/montecristo/dse-stats-converter /opt/montecristo-src/build/install/dse-stats-converter \
    && ln -sfn /opt/montecristo/old-c-stats-converter /opt/montecristo-src/build/install/old-c-stats-converter \
    && sed -i 's/^export COLLECTOR_S3_BUCKET=.*/export COLLECTOR_S3_BUCKET=unused/' /opt/montecristo-src/aws-env.sh \
    && sed -i '/^ y)$/,/^ ;;$/{s/run_cstats_conversion="true"/run_cstats_conversion="false"/}' /opt/montecristo-src/run.sh \
    && if ! ls /opt/montecristo-src/dse-stats-converter/libs/dse-db-all*.jar 1>/dev/null 2>&1; then \
         sed -i '/^ y)$/,/^ ;;$/{s/run_stats_conversion="true"/run_stats_conversion="false"/}' /opt/montecristo-src/run.sh; \
       fi

ENV PATH="/opt/montecristo/montecristo/bin:${PATH}"

COPY entrypoint.sh prepare-sperf-layout.sh run-sperf.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/prepare-sperf-layout.sh /usr/local/bin/run-sperf.sh

WORKDIR /ds-discovery
EXPOSE 1313

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--help"]
