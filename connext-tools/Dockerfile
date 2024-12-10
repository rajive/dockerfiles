FROM hectorm/xubuntu
LABEL maintainer="Rajive Joshi"

USER root

# neovim
RUN apt update && \
  apt install -y curl nodejs npm && \
  rm -rf /var/lib/apt/lists/*; \
  curl -sL https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz | tar -xzC /opt 2>&1

ENV PATH=/opt/nvim-linux64/bin:$PATH


# Add RTI's official public key
RUN curl -sSL -o /usr/share/keyrings/rti-official-archive.gpg \
  https://packages.rti.com/deb/official/repo.key

# Add the RTI repository to apt
RUN printf -- "deb [arch=%s, signed-by=%s] %s %s main\n" \
  $(dpkg --print-architecture) \
  /usr/share/keyrings/rti-official-archive.gpg \
  https://packages.rti.com/deb/official \
  $(. /etc/os-release && echo ${VERSION_CODENAME}) | \
  sudo tee /etc/apt/sources.list.d/rti-official.list >/dev/null

# Connext: update apt, accept license, and install
RUN apt update && \
  env RTI_LICENSE_AGREEMENT_ACCEPTED=accepted apt install -y rti-connext-dds-7.3.0-tools-all && \
  rm -rf /var/lib/apt/lists/*
