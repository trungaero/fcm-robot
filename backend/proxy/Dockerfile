# syntax=docker/dockerfile:1

# Reverse proxy with layer-4 (SNI) routing.
# Stock caddy:2 cannot route raw TCP/TLS, so caddy-l4 is compiled in.
FROM caddy:2-builder AS builder
RUN xcaddy build --with github.com/mholt/caddy-l4

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile

EXPOSE 443 80

# caddy validate runs the same parse path as startup, so a bad Caddyfile fails fast.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s CMD caddy validate --config /etc/caddy/Caddyfile || exit 1
