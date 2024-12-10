FROM rticom/connext-sdk
LABEL maintainer="Rajive Joshi"

USER root

# neovim
RUN apt update && \
  apt install -y curl nodejs npm && \
  rm -rf /var/lib/apt/lists/*; \
  curl -sL https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz | tar -xzC /opt 2>&1

ENV PATH=/opt/nvim-linux64/bin:$PATH


# RTI Connext
RUN ln -s $NDDSHOME /opt/rti.com/NDDSHOME

USER rtiuser
WORKDIR /home/rtiuser

ENTRYPOINT ["/opt/rti.com/NDDSHOME/bin/rtientrypoint"]
