FROM hectorm/xubuntu
LABEL maintainer="Rajive Joshi"

ARG CONNEXT_VERSION=7.7.0

USER root

# dev utils
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  curl \
  wget \
  unzip \
  fonts-jetbrains-mono \
  kitty-terminfo \
  imagemagick \
  libmagickwand-dev \
  plantuml \
  clangd \
  && \
  rm -rf /var/lib/apt/lists/*

RUN update-ca-certificates

# Add RTI's official public key
RUN curl -sSL -o /usr/share/keyrings/rti-official-archive.gpg \
  https://packages.rti.com/deb/official/repo.key

# Add the RTI repository to apt
RUN printf -- "deb [arch=%s, signed-by=%s] %s %s main\n" \
  $(dpkg --print-architecture) \
  /usr/share/keyrings/rti-official-archive.gpg \
  https://packages.rti.com/deb/official \
  $(. /etc/os-release && echo ${VERSION_CODENAME}) | \
  tee /etc/apt/sources.list.d/rti-official.list >/dev/null

# Connext: update apt, accept license, and install
RUN apt update && \
  env RTI_LICENSE_AGREEMENT_ACCEPTED=accepted apt install -y rti-connext-dds-${CONNEXT_VERSION}-tools-all && \
  rm -rf /var/lib/apt/lists/*
