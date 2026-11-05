FROM node:24-bookworm-slim

ARG S6_OVERLAY_VERSION=3.2.3.2
# Track the npm `next` dist-tag so the image installs the upcoming DSH release.
# Override this build arg (or the workflow's dsh_version input) to pin an exact
# release or go back to the `latest` stable dist-tag.
ARG DSH_VERSION=next
# Empty lets the mise installer pick its newest release (>=24h old); set it
# (e.g. 2026.11.1) to pin the mise binary for reproducible builds.
ARG MISE_VERSION=

# DSH requires Node.js 24.9+; the node:24 image already satisfies that.
ENV DEBIAN_FRONTEND=noninteractive \
    DSH_HOME=/data/dsh \
    TZ=Asia/Shanghai \
    PATH=/command:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Toolchain defaults, mirroring ../aiclaw-docker. The toolchains themselves
# are not preinstalled; these just make runtimes added later (via mise, the Go
# tarball, or rustup) work without extra configuration.
#   - mise: /root/.local/bin (mise binary; shims are intentionally NOT on PATH
#     so they cannot shadow the image's global node/npm/pnpm)
#   - dotnet: /root/.local/share/mise/dotnet-root (mise's dotnet install dir)
#   - Go: GOROOT=/root/.local/go, with $GOPATH/bin and $GOROOT/bin on PATH
#   - Rust: /root/.cargo/bin on PATH, with .cargo/env sourced in .bashrc
ENV GOROOT=/root/.local/go \
    GOPATH=/root/.local/share/go \
    PATH="${PATH}:/root/.local/bin:/root/.local/share/mise/dotnet-root:/root/.local/go/bin:/root/.local/share/go/bin:/root/.cargo/bin"
RUN mkdir -p "$GOPATH/bin" /root/.local/share/mise/dotnet-root /root/.cargo/bin \
    && printf 'if [ -f "$HOME/.cargo/env" ]; then . "$HOME/.cargo/env"; fi\n' >> /root/.bashrc

# GitHub CLI (gh) comes from its official apt repo so it stays updatable.
# The published keyring is already a binary OpenPGP keyring, so it can be
# written straight to /usr/share/keyrings without gnupg/dearmor.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      mawk \
      python3 \
      xz-utils; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    chmod 0644 /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends gh; \
    rm -rf /var/lib/apt/lists/*; \
    gh --version

# Install mise (polyglot toolchain manager). Download first rather than piping
# into sh so a curl failure is not masked by dash's lack of pipefail. Only the
# binary goes into /root/.local/bin; shims are not enabled globally so the
# image's node/npm/pnpm stay intact until a user opts into mise activation.
RUN set -eux; \
    curl -fsSL https://mise.run -o /tmp/mise-install.sh; \
    MISE_INSTALL_HELP=0 MISE_VERSION="${MISE_VERSION}" sh /tmp/mise-install.sh; \
    rm -f /tmp/mise-install.sh; \
    mise --version

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
