# syntax=docker/dockerfile:1

# LiveKit SFU with the embedded TURN server.
# Pin LIVEKIT_VERSION; config keys and TURN behaviour change between releases.
ARG LIVEKIT_VERSION=v1.9.0
FROM livekit/livekit-server:${LIVEKIT_VERSION}

# The upstream image is Alpine-based and ships no default config.
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY livekit.tpl.yaml /etc/livekit/livekit.tpl.yaml

ENV LIVEKIT_CONFIG=/etc/livekit/livekit.yaml

# 7880 signaling | 7881 ICE-TCP | 7882 media UDP | 3478 TURN UDP | 5349 TURN TLS | 6789 metrics
EXPOSE 7880/tcp 7881/tcp 7882/udp 3478/udp 5349/tcp 6789/tcp

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["--config", "/etc/livekit/livekit.yaml"]
