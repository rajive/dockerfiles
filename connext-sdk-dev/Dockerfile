ARG CONNEXT_VERSION=latest
FROM rticom/connext-sdk:${CONNEXT_VERSION}

LABEL org.opencontainers.image.authors="Rajive Joshi" \
  org.opencontainers.image.title="connext-sdk-dev" \
  org.opencontainers.image.description="RTI Connext SDK development image with Neovim and Node.js tooling"

USER root

# neovim (latest)
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  ca-certificates='*' \
  curl='*' \
  lua5.1='*' \
  luarocks='*' \
  nodejs='*' \
  npm='*' && \
  update-ca-certificates && \
  arch="$(dpkg --print-architecture)" && \
  case "$arch" in \
  amd64) neovim_package='nvim-linux-x86_64' ;; \
  arm64) neovim_package='nvim-linux-arm64' ;; \
  *) printf 'Unsupported architecture: %s\n' "$arch" >&2; exit 1 ;; \
  esac && \
  rm -rf /var/lib/apt/lists/* && \
  rm -rf "/opt/${neovim_package}" && \
  curl -fsSL -o "/tmp/${neovim_package}.tar.gz" "https://github.com/neovim/neovim/releases/latest/download/${neovim_package}.tar.gz" && \
  tar -xzf "/tmp/${neovim_package}.tar.gz" -C /opt && \
  rm -f "/tmp/${neovim_package}.tar.gz" && \
  ln -sf "/opt/${neovim_package}/bin/nvim" /usr/local/bin/nvim


# RTI Connext
RUN ln -s "$NDDSHOME" /opt/rti.com/NDDSHOME

USER rtiuser
WORKDIR /home/rtiuser

ENTRYPOINT ["/opt/rti.com/NDDSHOME/bin/rtientrypoint"]
