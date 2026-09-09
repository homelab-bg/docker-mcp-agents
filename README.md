# MCP test stack — HA / UniFi (Network+Protect+Access) / TrueNAS

## Setup

1. Copy `.env.example` to `.env` and fill in the non-secret values (hostnames, usernames).
2. Create the secret files (never commit these — the root `.gitignore` already excludes `secrets/*` and `.env`):
   ```
   echo -n 'your-ha-long-lived-token'      > secrets/ha_token.txt
   echo -n 'your-unifi-password'           > secrets/unifi_password.txt
   echo -n 'your-truenas-api-key'          > secrets/truenas_api_key.txt
   cat > secrets/aws_credentials <<'EOF2'
   [default]
   aws_access_key_id = your-access-key-id
   aws_secret_access_key = your-secret-access-key
   EOF2
   chmod 644 secrets/*
   ```
   `aws_credentials` is for the `caddy` service's Route53 DNS-01 challenge — standard AWS
   credentials file format, same as `docker-infisical`'s Caddy setup. Needs Route53
   permissions only (`ListHostedZones`, `GetChange`, `ChangeResourceRecordSets`).
   `644` not `600` — standalone Compose (non-Swarm) implements file-based `secrets:` as a
   bind-mount of the host file, keeping its host-side ownership and permissions rather
   than re-wrapping it for generic in-container access the way Swarm's native secrets do.
   Each image runs its process as its own non-root UID internally, which won't generally
   match your host user's UID, so `600` (owner-only) causes `Permission denied` reading
   `/run/secrets/<name>` for every image except one you happen to control (like our own
   `truenas-mcp`, where we picked the UID ourselves). This doesn't weaken isolation
   between services — each container still only ever sees the secrets explicitly listed
   under its own `secrets:` block in the compose file, regardless of file permissions.
   `unifi_password.txt` is shared across all three UniFi services — Network, Protect, and
   Access all authenticate with the same local admin account here (confirmed no 2FA/SSO
   MFA, which the servers don't support anyway). If you later create dedicated per-app
   service accounts instead, split this back into three separate secrets/files (one per
   service, each with its own `UNIFI_PASSWORD_FILE` path) — trivial to redo since the
   compose structure already isolates each service on its own network.
3. Make the entrypoint scripts executable (Docker preserves the bind-mounted file's exec bit from the host):
   ```
   chmod +x entrypoints/*.sh
   ```
4. **Pull and build the images** before you can inspect them — `docker inspect` only reads
   what's already local, it doesn't reach out to the registry:
   ```
   docker compose pull          # fetches ha-mcp and all three unifi-*-mcp images
   docker compose build truenas-mcp caddy
   ```
   `truenas-mcp` and `caddy` both set `pull_policy: build` (confirmed live this is needed -
   without it, `docker compose pull` tries to pull their `image:` tags from a registry
   where they don't exist, failing with "access denied ... repository does not exist",
   even though they're build-only). `docker compose up -d` alone would build them
   automatically regardless; pulling/building explicitly here is just to get them local
   before the inspect step below.
5. **Verified** — all four images pull cleanly and their `docker inspect` output confirms
   every pinned tag is real:
   ```
   $ docker inspect ghcr.io/homeassistant-ai/ha-mcp:8.4.3       --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'
   [] [fastmcp run fastmcp.json]
   $ docker inspect ghcr.io/sirkirby/unifi-network-mcp:0.32.1   --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'
   [] [unifi-network-mcp]
   $ docker inspect ghcr.io/sirkirby/unifi-protect-mcp:0.8.2    --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'
   [] [unifi-protect-mcp]
   $ docker inspect ghcr.io/sirkirby/unifi-access-mcp:0.6.1     --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'
   [] [unifi-access-mcp]
   ```
   Three of the four run their binary directly, matching the project name — `ha-mcp` is
   the one exception, running via `fastmcp run fastmcp.json` instead. Either way, every
   wrapper script here uses `exec "$@"` rather than a hardcoded binary name (see below),
   so none of this required editing any wrapper — the images already do the right thing
   once the secret is injected, regardless of what their actual CMD turns out to be.
   (`truenas-mcp` isn't in this list — that Dockerfile is ours, so its entrypoint is
   already known rather than needing inspection.)
6. `docker compose up -d`

## Why `secrets:` instead of `environment:`

With a secret passed as a plain `environment:` value, anyone with access to the Docker
socket/API — not just someone with a shell in the container — can read it back out in
plaintext, because it's stored as part of the container's own config:

```
$ docker inspect ha-mcp --format '{{json .Config.Env}}'
["HOMEASSISTANT_URL=http://ha.example.com:8123","HOMEASSISTANT_TOKEN=eyJhbGciOiJIUzI1NiIs...","PATH=..."]
```

That's visible to `docker inspect`, `docker compose config`, log aggregators that dump
container metadata, and anyone who can run `docker ps`/`docker inspect` against your
Docker host — a much wider blast radius than "someone got a shell in the container."

With the `secrets:` + entrypoint-wrapper pattern used here, the token never becomes part
of the container's stored config at all. It's written to a tmpfs-backed file at
`/run/secrets/ha_token` (readable only inside that specific container's mount namespace),
and only becomes a process env var *after* the entrypoint script runs, inside the running
process itself:

```
$ docker inspect ha-mcp --format '{{json .Config.Env}}'
["HOMEASSISTANT_URL=http://ha.example.com:8123","PATH=..."]

$ docker exec ha-mcp env | grep HOMEASSISTANT_TOKEN
HOMEASSISTANT_TOKEN=eyJhbGciOiJIUzI1NiIs...
```

Same value, much narrower exposure — `docker inspect` (and anything that reads container
config without ever touching the running container's internals) no longer leaks it.

## Why `exec "$@"` instead of a hardcoded binary name

The first version of these wrapper scripts ended in `exec ha-mcp "$@"` — a guess at the
image's binary name, taken from the project's own name rather than verified. Running
`docker inspect ghcr.io/homeassistant-ai/ha-mcp:8.4.3 --format '{{.Config.Entrypoint}}
{{.Config.Cmd}}'` showed the real command is `fastmcp run fastmcp.json` — the image runs
via the FastMCP framework, not a standalone `ha-mcp` binary. The guess would have failed
outright.

Most services here only override `entrypoint:` in Compose and leave `command:` unset, so
Docker automatically passes each image's original `CMD` through as arguments to the
wrapper script — `exec "$@"` re-runs exactly what the image would have run anyway, after
the wrapper has injected the secret, with no need to know or guess the binary name.
`ha-mcp` is the one exception (see Transports below) — it needs an explicit `command:`
override to force HTTP transport, but the wrapper script itself is unchanged; `exec "$@"`
just re-runs whatever command it's handed, whether that's the image's default or an
explicit override.

## Transports

MCP's `stdio` transport treats stdin closing as the shutdown signal — it's built for a
client to spawn the server as a subprocess with stdin/stdout held open for the session.
`docker compose up -d` runs containers detached with no stdin attached at all, so a
server defaulting to stdio sees immediate EOF, exits cleanly (code `0`), and Compose's
`restart: unless-stopped` relaunches it into the same loop forever. All five services
here default to stdio; each needed switching to an HTTP-based transport to run as a
persistent background service instead.

**`unifi-network-mcp`, `unifi-protect-mcp`, `unifi-access-mcp`** need no configuration
at all — confirmed live: each detects it's running as the container's main process
(PID 1) and automatically switches to Streamable HTTP on port `3000`, logging
*"Container main process (PID 1): running Streamable HTTP transport only."* No
`--transport` flag, no env var, nothing to set.

**`ha-mcp`** does not get this auto-detection — it runs via the plain FastMCP CLI
(`fastmcp run fastmcp.json`), which defaults to stdio regardless of context. Fixed with
an explicit `command:` override in the compose file:
```
command: ["fastmcp", "run", "fastmcp.json", "--transport", "http", "--host", "0.0.0.0", "--port", "8000"]
```

**`truenas-mcp`** (community `truenas-ws-mcp` by `thoriphes` — not to be confused with
`vespo92/TrueNasCoreMCP`, an unrelated project for the older TrueNAS Core product line)
needed source inspection to resolve, since its own console script offers no CLI flags at
all — `--help` was silently ignored rather than erroring, because there's no argument
parsing to catch it. Inspecting the installed package directly
(`truenas_ws_mcp/server.py`) showed it calls `mcp.run()` with no transport argument —
hardcoded to FastMCP's stdio default, with no env var or flag to override. Fixed the
same way as `ha-mcp`, pointing `fastmcp run` at the server object directly since it
bypasses the package's own script logic entirely and calls `.run()` itself — but it
needs an actual **file path** before the `:object`, not a dotted Python module path
(`truenas_ws_mcp.server:mcp` failed outright — `"File not found: /truenas_ws_mcp.server"`,
treated as a filesystem path rather than `import`ed). Rather than hardcode a
`python3.12`-specific site-packages path in the compose file (fragile — breaks silently
on the next Python version bump in the Dockerfile), the entrypoint wrapper resolves it
at runtime via Python's own import machinery:
```sh
SERVER_FILE="$(python3 -c 'import truenas_ws_mcp.server as m; print(m.__file__)')"
exec fastmcp run "${SERVER_FILE}:mcp" "$@"
```
`docker-compose.yml`'s `command:` for this service is now just the transport flags
(`--transport http --host 0.0.0.0 --port 8000`) — the wrapper builds the full
`fastmcp run <resolved-path>:mcp` invocation around them.

## Connecting from Claude Desktop

No ports are published directly to the Docker host - `caddy` is the sole entry point
(see "TLS via Caddy" below), same convention as every other reverse-proxied stack in
this pipeline. Container-side ports are each confirmed via logs - Network, Protect,
and Access each default to a *different* internal port, not all `3000` as initially
assumed - but none of that is reachable except through Caddy.

In Claude Desktop: **Settings → Connectors → Add → Custom → Web**. Enter a name and
the HTTPS hostname URL (e.g. `https://unifi-network-mcp.example.com/mcp`). Claude
checks the URL and attempts to auto-detect the authentication mode; since none of
these servers have an auth layer in front of them yet (Caddy adds TLS, not auth - see
Authentication below), select **None** if it isn't detected automatically (there are
open reports of the auto-detection misfiring even for genuinely unauthenticated
servers - a real known issue, not something to assume is a config mistake on this end).

This is fine for testing over the trusted home LAN as-is, but these are bare,
unauthenticated HTTPS endpoints - don't expose them further (Cloudflare Tunnel or
otherwise) without adding an auth layer in front first.

## TLS via Caddy (self-contained, no separate proxy stack)

A single `caddy` service in `docker-compose.yml` fronts all five backends with real,
Let's Encrypt-issued certs via DNS-01 (Route53) — same pattern as `docker-infisical`'s
own Caddy setup. No port 80 needed at all, and no requirement for this host to be
internet-reachable to issue a valid cert — DNS-01 proves domain control through DNS,
not through a publicly-reachable server.

**Why this instead of fronting these with `docker-traefik-portainer`:** that would
need Traefik itself attached to these five networks from its own separate compose
project, which can't happen atomically in the same `docker compose up` that creates
them here — a real startup-order race (Traefik's override referencing them as
`external: true` before this project has ever created them, or after a host reboot
where creation order isn't guaranteed). Keeping the proxy inside this project avoids
that class of problem entirely — one `docker compose up`, one atomic creation of
networks and the proxy together, no cross-project ordering dependency.

**Network design:** `caddy` is the only service here that joins more than one
network — all five backends' private networks, since it's the single trusted ingress
point that legitimately needs reachability to each. Every other service still only
joins its own private network, so the isolation model from the base file holds: the
five MCP services still can't reach each other, only `caddy` can reach each of them
individually. Custom-built image (`caddy/Dockerfile`, `caddy-dns/route53` plugin) for
the same reason as `docker-infisical`'s Caddy — it terminates TLS in front of live
HA/UniFi/TrueNAS control, so trusting a random pre-built `caddy+route53` image off
Docker Hub for that is a real supply-chain question, not just convenience.

Hostnames use `<service>.example.com` in this repo — substitute your own domain.
Using a subdomain of a domain you already have hosted in Route53 (rather than a
top-level domain of its own) means `caddy-dns/route53` finds the right hosted zone
automatically — it walks up the domain hierarchy to the closest match in the account,
no separate delegated zone needed. These hostnames don't need to resolve to a real
routable IP anywhere — DNS-01 only cares about the `_acme-challenge` TXT record it
creates and removes itself; whatever the hostname actually resolves to (or doesn't,
publicly) is unrelated to certificate issuance.

Cert storage (`caddy_data` volume, mounted at `/data`) needs to persist across
restarts — without it, every restart re-issues certs and risks hitting Let's
Encrypt's rate limits.

**This gets you TLS and a real domain. It does not add authentication on its own.**
None of these five servers have their own login — anyone who can resolve and reach
the configured hostname can use them. See Authentication below before relying on this
for anything beyond local testing.

## Authentication

**Not built yet - the single biggest thing before this stack should be trusted with
anything beyond LAN-only testing.** None of these five servers have their own login;
anyone who can resolve and reach a configured hostname can use them as-is.

Caddy has its own `forward_auth` directive (native since 2.7, equivalent to Traefik's
forward-auth middleware) — `caddy/Caddyfile` has a commented-out block sketching what
wiring in a self-hosted SSO (e.g. Authentik) would look like once one exists: an
outpost endpoint reachable from the `caddy` container (typically
`authentik-server:9000` with path `/outpost.goauthentik.io/auth/caddy`, per
Authentik's own Caddy integration docs), with the same cross-project-reachability
question the Traefik design avoided for the five backends - just for one container
this time. Uncomment and adjust once an actual auth provider is in place.

## Credentials

The three upstream projects here split into two groups, discovered by testing rather
than assumed from docs alone:

**`unifi-network-mcp`, `unifi-protect-mcp`, `unifi-access-mcp`** natively support the
`_FILE` convention — confirmed directly in the project's own README: *"set
`UNIFI_PASSWORD_FILE` to a path whose contents are the password instead... The same
`_FILE` suffix works on `UNIFI_API_KEY` and on the per-server variables."* This is the
same mechanism Postgres's official image implements via its `file_env` helper — Docker's
`secrets:` mechanism does all the work, no wrapper script needed. Each of the three
services just sets e.g. `UNIFI_PASSWORD_FILE: /run/secrets/unifi_password`
directly in `environment:`, with the matching secret mounted via `secrets:`.

**`ha-mcp` and `truenas-ws-mcp` do not support this** — confirmed by directly testing
`HOMEASSISTANT_TOKEN_FILE` against `ha-mcp`, which failed outright with a validation
error demanding `HOMEASSISTANT_TOKEN` be set directly; no evidence of equivalent support
for `truenas-ws-mcp` either. That's the same situation as Infisical's own
`ENCRYPTION_KEY`/`AUTH_SECRET`/DB credentials in `docker-infisical` — no file-based
support, so the honest move is to work with what the app actually supports rather than
force a mechanism it doesn't.

Where this deployment diverges from `docker-infisical`'s answer to that same problem:
`docker-infisical` fell back to a plain, gitignored `.env` for Infisical's own creds,
because those values are already gated behind other controls (self-hosted, single
operator, no public exposure) and Infisical's own official self-hosting guide sanctions
`.env` for them. Here, the values themselves (a long-lived HA token, a TrueNAS API key)
are live credentials to core home infrastructure — enough to be worth the extra layer
even without native support. So `ha-mcp` and `truenas-mcp` each get a small entrypoint
wrapper (`entrypoints/*.sh`) that reads its secret from a Compose-mounted
`/run/secrets/<name>` file and exports it as the env var the binary actually expects,
immediately before `exec`ing the real process. This gets the same `docker inspect`
blast-radius reduction as the UniFi services' native support, via a mechanism suited to
apps that only accept direct env vars.

If `ha-mcp` or `truenas-ws-mcp` add native file-based credential support later, drop
their wrapper scripts entirely and switch to the same direct `_FILE` pattern already
used for the three UniFi services.

## Version pinning

The `unifi-network-mcp`/`protect`/`access` versions above were confirmed current against
PyPI's release history on 8 Sep 2026 — `sirkirby/unifi-mcp` ships very frequently
(multiple releases most days) and has a documented history of yanking broken releases
from PyPI due to unbounded internal dependency versions (`unifi-network-mcp` 0.7.0–0.14.12,
`unifi-protect-mcp` 0.1.0–0.4.0, `unifi-access-mcp` 0.1.0–0.2.3 were all yanked). None of
our pinned versions fall in a yanked range, but this project's pace and yank history is
worth building into whatever version-bump pipeline comes next — check the release history
for yank notices before pinning a new version, not just whether it exists.

## Notes

- **All three `unifi-*-mcp` services need `UNIFI_MCP_ENABLE_DNS_REBINDING_PROTECTION=false`** -
  their own DNS-rebinding protection (`ha-mcp`/`truenas-mcp` don't have this) rejects every
  request behind Caddy with `Invalid Host header`, even with `UNIFI_MCP_ALLOWED_HOSTS` set
  correctly. Confirmed live by reading the pinned `0.32.3`'s actual installed source
  (`runtime.py`) inside the running container: the env var and its parsing are both genuinely
  correct (verified via `python3 -c` inside the container), so the mismatch is inside the
  package's own server construction, not anything on our side. Disabling the check is the
  project's own documented escape hatch for exactly this case ("proxy deployments where
  allowed_hosts is insufficient") - and it's a defense against malicious *browser* pages
  exploiting DNS rebinding, which doesn't apply to a deliberate HTTPS API client like Claude
  Desktop/Code behind our own TLS+DNS. `UNIFI_MCP_ALLOWED_HOSTS` is kept set too, in case a
  future release fixes the underlying issue and this can be re-enabled.
- **Claude Code confirmed working** - `claude mcp add --transport http <name>
  https://<host>.lan.homelab.green/mcp` for each of the 5, then `claude mcp get <name>` reports
  `✔ Connected` for all of them (a real health check, not just a config write).
- No version-bump automation exists yet. `sirkirby/unifi-mcp` ships very frequently and
  has a real history of yanking broken releases from PyPI (see Version pinning above) -
  any automation here needs to check for yank notices, not just whether a new tag exists.
- Non-secret values (`HOMEASSISTANT_URL`, `UNIFI_HOST`, `UNIFI_USERNAME`, `TRUENAS_URL`) are still
  plain `environment:` entries — nothing sensitive about a hostname or username, no need
  to route those through secrets.
- `TRUENAS_VERIFY_SSL` and `UNIFI_VERIFY_SSL` are set to `"false"` to match your
  self-signed local certs — tighten this if you put real certs on these services later.
- Each service is on its own Docker network with no shared network between them —
  see the compose file comments for the isolation rationale.
- Sensitive-field redaction (`UNIFI_*_REDACT_SENSITIVE_FIELDS`) is left at its default
  (on) for all three UniFi services — deliberate, not an oversight. Disabling it makes
  sense once there's a scoped-down local account dedicated to whatever workflow needs raw
  values, rather than doing it against the shared admin account all three services
  currently use.
- All three UniFi services' `tmpfs:` includes `/root/.config` alongside `/tmp` — the
  shared `unifi_core` library writes a session cache there, and `read_only: true`
  blocked it (`[Errno 30] Read-only file system: '/root/.config'`). Worth recognizing
  the pattern if it recurs elsewhere: the failed write triggered a retry loop that
  repeatedly re-attempted login against the controller, which is what surfaced as `429`
  rate-limiting in the logs — the real fault was the read-only filesystem, not the
  controller or the rate limit itself.
