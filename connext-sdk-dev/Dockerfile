# syntax=docker/dockerfile:1

FROM ubuntu:26.04 AS dev-base

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  git \
  curl \
  wget \
  unzip \
  tar \
  fonts-jetbrains-mono \
  kitty-terminfo \
  python3 \
  python3-venv \
  clangd \
  imagemagick \
  libmagickwand-dev \
  plantuml \
  libicu78 && \
  update-ca-certificates && \
  rm -rf /var/lib/apt/lists/*

FROM dev-base AS connext-sdk-dev

ARG CONNEXT_VERSION=7.7.0
ARG DEBIAN_FRONTEND=noninteractive
# RTI does not currently publish an Ubuntu 26.04 suite. Noble is the newest
# suite in the official repository and is used here as a compatibility source.
ARG RTI_REPOSITORY_SUITE=noble

ENV CONNEXT_VERSION=${CONNEXT_VERSION} \
  NDDSHOME=/opt/rti.com/rti_connext_dds-${CONNEXT_VERSION} \
  RTI_LICENSE_FILE=/opt/rti.com/rti_connext_dds-${CONNEXT_VERSION}/rti_license.dat

LABEL org.opencontainers.image.authors="Rajive Joshi" \
  org.opencontainers.image.title="connext-sdk-dev" \
  org.opencontainers.image.description="RTI Connext SDK Development"

RUN apt-get update && \
  apt-get install -y --no-install-recommends debconf-utils && \
  rm -rf /var/lib/apt/lists/*

RUN set -eu; \
  curl -fsSL -o /usr/share/keyrings/rti-official-archive.gpg \
  https://packages.rti.com/deb/official/repo.key; \
  printf 'deb [arch=%s signed-by=%s] %s %s main\n' \
  "$(dpkg --print-architecture)" \
  /usr/share/keyrings/rti-official-archive.gpg \
  https://packages.rti.com/deb/official \
  "${RTI_REPOSITORY_SUITE}" \
  > /etc/apt/sources.list.d/rti-official.list; \
  printf '%s\n' \
  "rti-connext-dds-${CONNEXT_VERSION}-common rti-connext-dds-${CONNEXT_VERSION}/license/accepted select true" \
  > /tmp/rti-debconf; \
  debconf-set-selections < /tmp/rti-debconf; \
  rm /tmp/rti-debconf

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  "rti-connext-dds-${CONNEXT_VERSION}" && \
  rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1010 rtigroup && \
  useradd --uid 1010 --gid rtigroup --create-home --shell /bin/bash rtiuser && \
  mkdir -p "/home/rtiuser/rti_workspace/${CONNEXT_VERSION}" && \
  chown -R rtiuser:rtigroup /home/rtiuser

COPY --chmod=0755 rtientrypoint /usr/local/bin/rtientrypoint

USER rtiuser
WORKDIR /home/rtiuser

ENTRYPOINT ["rtientrypoint"]
CMD ["bash"]
