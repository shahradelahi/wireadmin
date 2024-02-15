ARG ALPINE_VERSION=3.19

FROM --platform=$BUILDPLATFORM chriswayg/tor-alpine:latest as tor
FROM --platform=$BUILDPLATFORM node:alpine${ALPINE_VERSION} as base
LABEL Maintainer="Shahrad Elahi <https://github.com/shahradelahi>"
WORKDIR /app

ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY --from=tor /usr/local/bin/obfs4proxy /usr/local/bin/obfs4proxy
COPY --from=tor /usr/local/bin/meek-server /usr/local/bin/meek-server

# Update and upgrade packages
RUN apk update && apk upgrade &&\
  # Install required packages
  apk add -U --no-cache \
  iproute2 iptables net-tools \
  screen curl bash \
  wireguard-tools \
  tor &&\
  # NPM packages
  npm install -g @litehex/node-checksum &&\
  # Clear APK cache
  rm -rf /var/cache/apk/*

COPY /config/torrc.template /etc/tor/torrc.template

# Copy user scripts
COPY /bin /usr/local/bin
RUN chmod -R +x /usr/local/bin

COPY web/package.json web/pnpm-lock.yaml ./

# Base env
ENV PROTOCOL_HEADER=x-forwarded-proto
ENV HOST_HEADER=x-forwarded-host


FROM base AS build

# Setup Pnpm - Pnpm only used for build stage
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

COPY web .

RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile \
    # build
    && NODE_ENV=production pnpm run build \
    # Omit devDependencies
    && pnpm prune --prod \
    # Move the goods to a temporary location
    && mv node_modules /tmp/node_modules \
    && mv build /tmp/build \
    # Remove everything else
    && rm -rf ./*


FROM base AS release

# Copy the goods from the build stage
COPY --from=build /tmp/node_modules node_modules
COPY --from=build /tmp/build build

# Fix permissions
RUN mkdir -p /data && chmod 700 /data
RUN mkdir -p /etc/torrc.d && chmod -R 400 /etc/torrc.d
RUN mkdir -p /var/vlogs && touch /var/vlogs/web && chmod -R 600 /var/vlogs

ENV NODE_ENV=production
ENV LOG_LEVEL=error

# Setup entrypoint
COPY docker-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Healthcheck
HEALTHCHECK --interval=60s --timeout=3s --start-period=20s --retries=3 \
 CMD curl -f http://127.0.0.1:3000/api/health || exit 1

# Volumes
VOLUME ["/etc/torrc.d", "/data", "/var/vlogs"]

# Overwrite package version
ARG VERSION=0.0.0-canary
RUN node -e "const fs = require('fs'); const pkg = JSON.parse(fs.readFileSync('/app/package.json')); pkg.version = process.env.VERSION; fs.writeFileSync('/app/package.json', JSON.stringify(pkg, null, 2));"

# Run the app
EXPOSE 3000/tcp
CMD [ "npm", "run", "start" ]
