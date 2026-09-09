#!/bin/sh
set -eu

# Read the secret from its tmpfs-backed file and export it only as a
# process-level env var inside this container — never stored in the
# container's config, so it won't show up in `docker inspect`.
export HOMEASSISTANT_TOKEN="$(cat /run/secrets/ha_token)"

# exec "$@" rather than a hardcoded binary name: Compose only overrides
# `entrypoint:` here (never `command:`), so Docker passes the image's
# original CMD through as arguments to this script — whatever that
# actually is (confirmed via `docker inspect` to be `fastmcp run
# fastmcp.json` for this image, not a standalone `ha-mcp` binary as
# the project name suggests). This way the wrapper doesn't need to
# know or guess the binary name at all.
exec "$@"
