# Pinned exact versions, same convention as every other image in this repo
# (mcp-caddy, truenas-mcp) - confirmed live against the real npm registry
# and Docker Hub rather than floating on `latest`/`22-alpine`.
FROM node:22.23.2-alpine

# @anthropic-ai/claude-code requires Node >=22.0.0 (confirmed via
# `npm view @anthropic-ai/claude-code engines`).
RUN npm install -g @anthropic-ai/claude-code@2.1.266

# No official Anthropic-published image for this - Remote Control's own docs
# don't document a containerization path at all, this is us wrapping the CLI
# ourselves. Runs as a non-root user (image already ships a `node` user) -
# claude-code doesn't need root for anything it does here.
USER node
WORKDIR /workspace

ENTRYPOINT ["/bin/sh", "-c"]
