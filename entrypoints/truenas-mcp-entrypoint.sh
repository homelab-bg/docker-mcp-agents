#!/bin/sh
set -eu

export TRUENAS_API_KEY="$(cat /run/secrets/truenas_api_key)"

# Resolve the installed package's server.py path at runtime via Python's own
# import machinery, rather than hardcoding a python3.12-specific site-packages
# path in docker-compose.yml — this stays correct across Python version bumps
# in the Dockerfile without needing a matching edit in the compose file.
SERVER_FILE="$(python3 -c 'import truenas_ws_mcp.server as m; print(m.__file__)')"

# "$@" here is just the transport flags (--transport http --host ... --port ...)
# passed via compose `command:` — fastmcp run itself and the resolved file:object
# path are constructed here, not passed in from compose.
exec fastmcp run "${SERVER_FILE}:mcp" "$@"
