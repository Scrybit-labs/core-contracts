# ⚠️ VERSION MANAGED BY dc TOOL ⚠️
# These versions are replaced by dc during template instantiation
ARG NODE_VERSION=latest
ARG YARN_VERSION=4.12.0
FROM mcr.microsoft.com/devcontainers/javascript-node:${NODE_VERSION}

# Install SSH server, tmux, and gawk (required for ble.sh)
RUN apt-get update && \
    apt-get install -y openssh-server tmux gawk && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd


# Re-declare ARG after FROM to use it in RUN commands
ARG YARN_VERSION

# Remove pre-installed Yarn 1.x and enable Corepack for Yarn 4.x
RUN rm -rf /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg && \
    corepack enable && \
    corepack prepare yarn@${YARN_VERSION} --activate
