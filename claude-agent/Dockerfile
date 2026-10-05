# Pinned exact versions, same convention as every other image in this repo
# (mcp-caddy, truenas-mcp) - confirmed live against the real npm registry
# and Docker Hub rather than floating on `latest`/`22-alpine`.
FROM node:22.23.2-alpine

# @anthropic-ai/claude-code requires Node >=22.0.0 (confirmed via
# `npm view @anthropic-ai/claude-code engines`).
RUN npm install -g @anthropic-ai/claude-code@2.1.266

# Alpine only ships BusyBox ash as /bin/sh - no bash, and nothing sets
# $SHELL - confirmed live this breaks the Bash tool entirely ("No suitable
# shell found") before any command even runs, not a bad-command error.
# openssh-client is just as load-bearing as bash here: this container's
# whole point is reaching out to LAN devices (e.g. diagnosing the SMHub
# NanoMR6), and a shell with no way to SSH anywhere doesn't get you far.
# git lets fixes found from in here actually get committed, not just
# diagnosed. The rest are standard diagnostic tools that come up
# constantly and are missing from a bare Alpine image (dig/nslookup, ping,
# nc, the modern `ip` command instead of deprecated net-tools, jq for
# parsing REST API/docker inspect output, rsync for file sync/backups).
# Deliberately no sshpass - password-based SSH scripting is a bad habit
# (credentials leak into process lists/shell history); use key auth.
RUN apk add --no-cache \
    curl bash git openssh-client \
    iputils bind-tools netcat-openbsd iproute2 \
    jq rsync
ENV SHELL=/bin/bash

# No official Anthropic-published image for this - Remote Control's own docs
# don't document a containerization path at all, this is us wrapping the CLI
# ourselves. Runs as a non-root user (image already ships a `node` user) -
# claude-code doesn't need root for anything it does here.
USER node
WORKDIR /workspace

# Pulled from a separate public repo (github.com/homelab-bg/ai-working-rules)
# so the same working-style rules used interactively can be reused across
# other projects, not just this one. Pinned to a tag, not `main` - confirmed
# live that raw.githubusercontent.com resolves tags the same as commits, and
# this matches the pin-everything convention used for every other version in
# this repo (a floating branch ref would make the build's behavior depend on
# whatever that repo's main happens to be at build time, with no diff in this
# repo's own history to explain why). Bump the tag deliberately to update.
# NOTE: only takes effect on a genuinely fresh `claude-agent-home` volume -
# Docker only auto-populates a named volume from the image on first mount,
# so an already-populated volume (like the one running today) needs a manual
# `docker cp` instead - see README's Setup section.
RUN mkdir -p /home/node/.claude && \
    curl -fsSL -o /home/node/.claude/CLAUDE.md \
      https://raw.githubusercontent.com/homelab-bg/ai-working-rules/2026.09.288afd8/CLAUDE.md

# No custom ENTRYPOINT - compose's `command:` is a real argv list (see
# docker-compose.yml), execed directly. Confirmed live: `ENTRYPOINT ["/bin/sh",
# "-c"]` + a multi-word command string is a real footgun here - only the
# first token after `-c` actually runs, everything else becomes `sh -c`'s own
# positional params ($0, $1...) and gets silently dropped, not appended to
# the command. That's what caused claude-agent to run bare `claude` (which
# then defaulted to expecting stdin/print input) instead of
# `claude remote-control ...`.
