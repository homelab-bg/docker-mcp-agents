# Pinned exact versions, same convention as every other image in this repo
# (mcp-caddy, truenas-mcp) - confirmed live against the real npm registry
# and Docker Hub rather than floating on `latest`/`22-alpine`.
FROM node:22.23.2-alpine

# @anthropic-ai/claude-code requires Node >=22.0.0 (confirmed via
# `npm view @anthropic-ai/claude-code engines`).
RUN npm install -g @anthropic-ai/claude-code@2.1.266

RUN apk add --no-cache curl

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
