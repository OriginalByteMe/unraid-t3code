# Headless T3 Code (`t3 serve`) for Unraid. amd64 only: Unraid and its
# Tailscale hook are x86_64.
FROM ubuntu:24.04

# Pinned; .github/workflows/t3-bump.yml opens a pull request for each release.
ARG T3CODE_VERSION=0.1.5
ENV DEBIAN_FRONTEND=noninteractive

# Docker CLI, GitHub CLI and Tailscale come from their vendors' apt repos.
# Tailscale is preinstalled so Unraid's "Use Tailscale" hook skips its own
# download on every start; the hook only needs jq and the two binaries.
# The lib* packages, fontconfig and fonts-liberation are what T3's headless
# browser loads, the list `t3 browser setup` installs. zsh, fish and tmux back
# the Shell setting.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl jq; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/github-cli.gpg; \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg -o /etc/apt/keyrings/tailscale.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list; \
    echo "deb [signed-by=/etc/apt/keyrings/github-cli.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list; \
    echo "deb [signed-by=/etc/apt/keyrings/tailscale.gpg] https://pkgs.tailscale.com/stable/ubuntu noble main" > /etc/apt/sources.list.d/tailscale.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      docker-ce-cli gh tailscale libvirt-clients \
      git openssh-client tini procps xz-utils unzip zsh fish tmux python3 \
      libnss3 libglib2.0-0t64 libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64 \
      libdbus-1-3 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 \
      libxrandr2 libxkbcommon0 libgbm1 libasound2t64 libexpat1 fontconfig fonts-liberation; \
    rm -rf /var/lib/apt/lists/*

# T3 Code's self-contained Linux build, checked against the release's SHA256SUMS.
RUN set -eux; \
    base="https://github.com/pingdotgg/t3code/releases/download/v${T3CODE_VERSION}"; \
    archive="t3-${T3CODE_VERSION}-linux-x64.tar.gz"; \
    sum=$(curl -fsSL "$base/SHA256SUMS" | grep " \*\{0,1\}${archive}\$" | cut -d' ' -f1); \
    curl -fsSL -o /tmp/t3.tar.gz "$base/$archive"; \
    echo "${sum}  /tmp/t3.tar.gz" | sha256sum -c -; \
    install -d /opt/t3code; \
    tar -xzf /tmp/t3.tar.gz -C /opt/t3code --strip-components=1; \
    rm /tmp/t3.tar.gz; \
    ln -s /opt/t3code/t3 /usr/local/bin/t3; \
    t3 --version

# Node for agent CLIs installed with npm and for ACP agents run with npx.
# Latest 24.x at build time, checked against nodejs.org's published sums.
RUN set -eux; \
    base=https://nodejs.org/dist/latest-v24.x; \
    line=$(curl -fsSL "$base/SHASUMS256.txt" | grep 'linux-x64.tar.xz$'); \
    curl -fsSL -o /tmp/node.tar.xz "$base/${line##* }"; \
    echo "${line%% *}  /tmp/node.tar.xz" | sha256sum -c -; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --exclude='*/CHANGELOG.md'; \
    rm /tmp/node.tar.xz; \
    node --version

# Bun, which omp and other Bun-based agent CLIs run on. The baseline build also
# runs on CPUs without AVX2, which many NAS boxes have.
RUN set -eux; \
    base=https://github.com/oven-sh/bun/releases/latest/download; \
    line=$(curl -fsSL "$base/SHASUMS256.txt" | grep ' bun-linux-x64-baseline.zip$'); \
    curl -fsSL -o /tmp/bun.zip "$base/bun-linux-x64-baseline.zip"; \
    echo "${line%% *}  /tmp/bun.zip" | sha256sum -c -; \
    unzip -j /tmp/bun.zip '*/bun' -d /usr/local/bin; \
    ln -s bun /usr/local/bin/bunx; \
    rm /tmp/bun.zip; \
    bun --version

# The runtime account, already 99:100 (Unraid's nobody:users); the entrypoint
# moves it when PUID/PGID differ. Interactive root bash (Unraid's Console
# button) becomes t3code in its shell, so agent logins land in t3code's home;
# `sh` still gives a root shell.
RUN useradd --no-log-init -u 99 -g users -m -d /home/t3code -s /bin/bash t3code \
 && install -d -o t3code -g users /projects \
 && echo '[ "$(id -u)" = 0 ] && export SHELL="$(getent passwd t3code | cut -d: -f7)" && exec setpriv --reuid="$(id -u t3code)" --regid="$(id -g t3code)" --init-groups "$SHELL"' >> /etc/bash.bashrc

# Docker's default seccomp profile blocks the user namespaces Chrome's sandbox
# needs, so T3's browser runs without it; the container is the boundary.
ENV HOME=/home/t3code \
    PATH=/home/t3code/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    NPM_CONFIG_PREFIX=/home/t3code/.local \
    T3CODE_SERVER_BROWSER_SANDBOX=0 \
    PUID=99 \
    PGID=100

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint
EXPOSE 3773
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
