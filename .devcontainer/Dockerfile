# =============================================================================
# YOLO Dev Sandbox — Minimal secure container
# =============================================================================
# Lean base with mise for tool management. Install what you need:
#   mise use node@22 python@3.12 go@1.23 rust@stable
# =============================================================================

FROM ubuntu:24.04

LABEL maintainer="yolo-dev-sandbox"
LABEL description="Minimal secure sandbox — use mise to install dev tools"

ENV DEBIAN_FRONTEND=noninteractive

# ---- Only the essentials ----
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    git-lfs \
    build-essential \
    pkg-config \
    unzip \
    zip \
    xz-utils \
    jq \
    ripgrep \
    fd-find \
    fzf \
    bat \
    tree \
    less \
    vim \
    htop \
    procps \
    openssh-client \
    locales \
    sudo \
    zsh \
    tmux \
    file \
    && rm -rf /var/lib/apt/lists/*

# ---- Locale ----
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# ---- Create non-root user ----
ARG USERNAME=sandbox
ARG USER_UID=1000
ARG USER_GID=1000

RUN EXISTING_USER=$(getent passwd ${USER_UID} | cut -d: -f1 || true) && \
    EXISTING_GROUP=$(getent group ${USER_GID} | cut -d: -f1 || true) && \
    if [ -n "$EXISTING_USER" ] && [ "$EXISTING_USER" != "${USERNAME}" ]; then userdel -r "$EXISTING_USER" 2>/dev/null || true; fi && \
    if [ -n "$EXISTING_GROUP" ] && [ "$EXISTING_GROUP" != "${USERNAME}" ]; then groupdel "$EXISTING_GROUP" 2>/dev/null || true; fi && \
    groupadd --gid ${USER_GID} ${USERNAME} && \
    useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/zsh ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# ---- Install mise (dev tool manager) ----
USER ${USERNAME}
RUN curl https://mise.run | sh && \
    echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc && \
    echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

# ---- Minimal zsh setup ----
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting && \
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc && \
    echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc

# ---- Create work directory ----
USER root
RUN mkdir -p /workspace /work && chown ${USERNAME}:${USERNAME} /workspace /work

USER ${USERNAME}
WORKDIR /work

CMD ["sleep", "infinity"]
