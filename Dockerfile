# Generic image — no user baked in. Identity is created at runtime by entrypoint.
# Using Debian slim (not Alpine) because mempalace → ChromaDB → onnxruntime needs glibc.
FROM node:20-slim

# Install essential tools and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    zsh \
    git \
    curl \
    wget \
    vim \
    nano \
    sudo \
    gosu \
    python3 \
    python3-pip \
    python3-venv \
    make \
    g++ \
    docker.io \
    openssh-client \
    ca-certificates \
    ripgrep \
    fd-find \
    jq \
    tree \
    less \
    patch \
    diffutils \
    findutils \
    coreutils \
    sed \
    gawk \
    grep \
    tar \
    gzip \
    unzip \
    xz-utils \
    sqlite3 \
    postgresql-client \
    redis-tools \
    procps \
    lsof \
    net-tools \
    dnsutils \
    strace \
    util-linux \
    && rm -rf /var/lib/apt/lists/*

# yq not in Debian repos — install binary (with retries for flaky Docker DNS)
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL --retry 3 --retry-delay 5 "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# Python packages (split into layers for better caching; generous timeout for large downloads)
RUN pip3 install --break-system-packages --timeout 120 --retries 3 \
    requests \
    httpx \
    pyyaml \
    toml \
    python-dotenv \
    pytest \
    black \
    ruff \
    mypy \
    ipython \
    rich \
    click \
    beautifulsoup4 \
    lxml \
    pandas \
    jinja2

# mempalace + its heavy deps (chromadb, onnxruntime) in a separate layer
RUN pip3 install --break-system-packages --timeout 300 --retries 3 \
    mempalace

# Install claude-code globally
RUN npm install -g @anthropic-ai/claude-code

# Common npm dev tools (split to avoid OOM during build)
RUN npm install -g typescript tsx
RUN npm install -g prettier eslint json-server

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Default working directory (overridden by -w at runtime)
WORKDIR /workspace

# Entrypoint creates the user at runtime and drops privileges via gosu
ENTRYPOINT ["entrypoint.sh"]
CMD ["bash"]
