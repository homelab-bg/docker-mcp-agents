#!/bin/sh
set -eu

export TRUENAS_API_KEY="$(cat /run/secrets/truenas_api_key)"

# Confirmed live: `fastmcp run <file>:mcp --transport http` (the previous
# approach here) accepts connections and answers `initialize` correctly, but
# `tools/list` comes back empty ({"tools":[]}) despite all 59 tools genuinely
# being registered - confirmed by importing the module directly and calling
# `mcp.list_tools()` in-process. Calling the FastMCP object's own `.run()`
# method programmatically instead does not have this problem - same module,
# same registered tools, real tools/list results. This matches a known class
# of FastMCP streamable-http session-handling issue (not unique to this
# package), not a bug in truenas_ws_mcp's own tool definitions.
exec python3 -c "
import truenas_ws_mcp.server as s
s.mcp.run(transport='http', host='0.0.0.0', port=8000)
"
