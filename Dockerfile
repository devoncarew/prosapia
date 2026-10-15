# The Prosapia server, as deployed to Cloud Run. Build and deploy with
# tool/deploy.sh; see docs/deploying.md.

# The server, compiled with its native libraries (sqlite).
FROM dart:3.12 AS server
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get
COPY bin bin
COPY lib lib
RUN dart build cli -t bin/prosapia.dart -o /out

# The browser code.
FROM node:22-slim AS web
WORKDIR /web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web ./
RUN npm run build

# The image that runs: the server, its pages' scripts, and the tools it
# calls for photos (exiftool for metadata, vips for display copies).
FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates libimage-exiftool-perl libvips-tools libheif1 \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=server /out/bundle ./
COPY --from=web /web/dist web/dist
COPY config config
COPY docs/writing.md docs/writing.md
# Cloud Run's disk is memory and is lost on restart; the cache is rebuilt.
ENV PROSAPIA_CACHE=/tmp/prosapia_cache
CMD ["/app/bin/prosapia"]
