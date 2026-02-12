# =============================================================================
# YOLO Dev Sandbox - Secure Devcontainer Environment
# =============================================================================
# A fully isolated sandbox where you can run ANY command without fear.
# Nothing inside this container can touch your host system.
# =============================================================================

FROM ubuntu:24.04

LABEL maintainer="yolo-dev-sandbox"
LABEL description="Secure sandbox for fearless development"

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# ---- Core system packages ----
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Essentials
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    # Build tools
    build-essential \
    cmake \
    pkg-config \
    autoconf \
    automake \
    libtool \
    # Version control
    git \
    git-lfs \
    # Editors & utilities
    vim \
    nano \
    less \
    jq \
    yq \
    tree \
    htop \
    ncdu \
    ripgrep \
    fd-find \
    fzf \
    bat \
    unzip \
    zip \
    xz-utils \
    # Networking & debugging
    net-tools \
    iputils-ping \
    dnsutils \
    netcat-openbsd \
    openssh-client \
    # Process management
    procps \
    lsof \
    strace \
    # Shell
    zsh \
    tmux \
    # Python (system — uv manages packages/venvs)
    python3 \
    # Database clients
    sqlite3 \
    postgresql-client \
    # Misc
    file \
    locales \
    sudo \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# ---- Set locale ----
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# ---- Install Node.js (LTS) ----
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g npm@latest \
    && npm install -g \
        yarn \
        pnpm \
        tsx \
        typescript \
        ts-node \
        nodemon \
        @devcontainers/cli

# ---- Install Go ----
ARG GO_VERSION=1.23.5
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-$(dpkg --print-architecture).tar.gz" \
    | tar -C /usr/local -xzf -
ENV PATH="/usr/local/go/bin:${PATH}"

# ---- Install Rust ----
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH="/usr/local/cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal \
    && chmod -R a+w ${CARGO_HOME}/registry || true

# ---- Install Docker CLI (for Docker-outside-of-Docker) ----
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# ---- Install GitHub CLI ----
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# ---- Install uv (fast Python package manager) ----
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# ---- Create non-root user 'sandbox' ----
ARG USERNAME=sandbox
ARG USER_UID=1000
ARG USER_GID=1000

# Remove existing user/group with target UID/GID if they exist, then create ours
RUN EXISTING_USER=$(getent passwd ${USER_UID} | cut -d: -f1 || true) && \
    EXISTING_GROUP=$(getent group ${USER_GID} | cut -d: -f1 || true) && \
    if [ -n "$EXISTING_USER" ] && [ "$EXISTING_USER" != "${USERNAME}" ]; then userdel -r "$EXISTING_USER" 2>/dev/null || true; fi && \
    if [ -n "$EXISTING_GROUP" ] && [ "$EXISTING_GROUP" != "${USERNAME}" ]; then groupdel "$EXISTING_GROUP" 2>/dev/null || true; fi && \
    groupadd --gid ${USER_GID} ${USERNAME} && \
    useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/zsh ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# ---- Setup Go paths for user ----
ENV GOPATH="/home/${USERNAME}/go"
ENV PATH="${GOPATH}/bin:${PATH}"
RUN mkdir -p ${GOPATH}/{bin,src,pkg} && chown -R ${USERNAME}:${USERNAME} ${GOPATH}

# ---- Fix Rust/Cargo permissions for sandbox user ----
RUN chown -R ${USERNAME}:${USERNAME} ${CARGO_HOME} ${RUSTUP_HOME}

# ---- Install Oh My Zsh for nicer shell experience ----
USER ${USERNAME}
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
    && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting \
    && sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc

# ---- Create workspace and working copy directories ----
USER root
RUN mkdir -p /workspace /work && chown ${USERNAME}:${USERNAME} /workspace /work

# ---- Healthcheck ----
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD [ "true" ]

USER ${USERNAME}
WORKDIR /work

# Keep container running
CMD ["sleep", "infinity"]
