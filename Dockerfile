FROM node:24-bookworm-slim

ARG S6_OVERLAY_VERSION=3.2.3.2
# Track the npm `latest` dist-tag so the :latest image always installs the
# newest published DSH. Override this build arg (or the workflow's dsh_version
# input) to pin an exact release.
ARG DSH_VERSION=latest

# DSH requires Node.js 24.9+; the node:24 image already satisfies that.
ENV DEBIAN_FRONTEND=noninteractive \
    DSH_HOME=/data/dsh \
    TZ=Asia/Shanghai \
    PATH=/command:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      python3 \
      xz-utils \
    && rm -rf /var/lib/apt/lists/*

# s6-overlay v3 keeps the container alive and supervises the DSH process,
# so restarting DSH does not stop the container or its volumes.
RUN set -eux; \
    arch="$(uname -m)"; \
    base="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}"; \
    curl -fsSL -o /tmp/s6-noarch.tar.xz "${base}/s6-overlay-noarch.tar.xz"; \
    curl -fsSL -o /tmp/s6-arch.tar.xz "${base}/s6-overlay-${arch}.tar.xz"; \
    tar -C / -Jxpf /tmp/s6-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-arch.tar.xz; \
    rm -f /tmp/s6-noarch.tar.xz /tmp/s6-arch.tar.xz

RUN npm install --global "@deepseek-ai/dsh@${DSH_VERSION}" pnpm@10 \
    && dsh --version

WORKDIR /workspace
COPY services.d/dsh /etc/services.d/dsh
RUN chmod 0755 /etc/services.d/dsh/run \
    && mkdir -p /data/dsh /workspace

EXPOSE 3080
ENTRYPOINT ["/init"]
