# Custom build, not a pre-built caddy+route53 image from Docker Hub — same
# reasoning as docker-infisical's caddy/Dockerfile: this container terminates
# TLS in front of live HA/UniFi/TrueNAS control, making it one of the more
# security-sensitive pieces in this stack. Trusting an unofficial,
# personally-maintained image for that is a real supply-chain question, not
# just convenience. Uses Caddy's own official builder + xcaddy pattern
# instead, with both the Caddy version and the plugin version pinned
# explicitly.
FROM caddy:2.11.4-builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/route53@v1.6.2

FROM caddy:2.11.4

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
