# Build: Swift 6 on Ubuntu 24.04, release mode, static Swift standard library.
FROM swift:6.1-noble AS build
WORKDIR /build
COPY Package.swift Package.resolved ./
RUN swift package resolve
COPY Sources ./Sources
RUN swift build -c release --product Run --static-swift-stdlib \
    && mkdir /staging && cp "$(swift build -c release --show-bin-path)/Run" /staging/

# Run: a small Ubuntu image with only what the binary needs.
FROM ubuntu:noble
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates tzdata libjemalloc2 \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --user-group --create-home --home-dir /app vapor
WORKDIR /app
COPY --from=build --chown=vapor:vapor /staging/Run /app/Run
USER vapor
ENV LD_PRELOAD=libjemalloc.so.2
# Render sets PORT.
CMD ["sh", "-c", "exec ./Run serve --env production --hostname 0.0.0.0 --port ${PORT:-8080}"]
