# Use Alpine Linux with Node.js for a lightweight image
FROM node:20-alpine

# Install essential tools and dependencies
RUN apk add --no-cache \
    bash \
    zsh \
    git \
    curl \
    wget \
    vim \
    nano \
    sudo \
    shadow \
    python3 \
    py3-pip \
    py3-virtualenv \
    make \
    g++ \
    musl-dev \
    linux-headers \
    libffi-dev \
    openssl-dev \
    docker-cli \
    openssh-client \
    ca-certificates \
    ripgrep \
    fd \
    jq \
    yq \
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
    xz \
    sqlite \
    postgresql16-client \
    redis \
    procps \
    lsof \
    net-tools \
    bind-tools \
    strace \
    && rm -rf /var/cache/apk/*

# Python packages (globally, Alpine style)
RUN pip3 install --break-system-packages \
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

# Install claude-code globally
RUN npm install -g @anthropic-ai/claude-code

# Common npm dev tools
RUN npm install -g \
    typescript \
    tsx \
    prettier \
    eslint \
    json-server

# Create non-root user with passwordless sudo
# Claude Code refuses to run as root (UID 0), so we create a regular user
# that has full sudo privileges without a password — same effective power as
# root but Claude will actually spawn.
RUN adduser -D -s /bin/bash -h /home/claude claude \
    && echo "claude ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/claude \
    && chmod 0440 /etc/sudoers.d/claude

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Set up working directory
WORKDIR /workspace
RUN chown claude:claude /workspace

# Switch to non-root user
USER claude

# Create writable config dir (host mount goes to .claude-host, entrypoint copies it here)
RUN mkdir -p /home/claude/.claude && chown claude:claude /home/claude/.claude

# Set environment variables
ENV CLAUDE_CONFIG_DIR=/home/claude/.claude

# Entrypoint fixes credential permissions then runs the command
ENTRYPOINT ["entrypoint.sh"]
CMD ["bash"]
