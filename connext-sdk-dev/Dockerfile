ARG CONNEXT_VERSION=7.7.0

FROM rticom/connext-sdk:${CONNEXT_VERSION}

LABEL org.opencontainers.image.authors="Rajive Joshi" \
  org.opencontainers.image.title="connext-sdk-dev" \
  org.opencontainers.image.description="RTI Connext SDK Development"

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

USER rtiuser
WORKDIR /home/rtiuser

ENTRYPOINT ["rtientrypoint"]
