ARG GLEAM_VERSION=v1.12.0

# Build stage - compile the application
FROM ghcr.io/gleam-lang/gleam:${GLEAM_VERSION}-erlang AS builder

# Add project code
COPY ./shared /build/shared
COPY ./client /build/client
COPY ./server /build/server

COPY ./server/index.html /build/server/priv/static/index.html
# RUN mkdir /build/server/priv/actions

# RUN apk add musl-dev

# Install dependencies for all projects
RUN cd /build/shared && gleam deps download
RUN cd /build/client && gleam deps download
RUN cd /build/server && gleam deps download

# Compile the client code and output to server's static directory
RUN cd /build/client \
  && gleam run -m lustre/dev build app --minify --outdir=/build/server/priv/static

# Compile the server code
RUN cd /build/server \
  && gleam export erlang-shipment

# Runtime stage - slim image with only what's needed to run
FROM ghcr.io/gleam-lang/gleam:${GLEAM_VERSION}-erlang-alpine

# Copy the compiled server code from the builder stage
COPY --from=builder /build/server/build/erlang-shipment /app

RUN apk add inotify-tools
RUN apk add envsubst

# Set up the entrypoint
WORKDIR /app
RUN echo -e '#!/bin/sh\n ERL_AFLAGS=$(echo "$ERL_AFLAGS" | envsubst) exec ./entrypoint.sh "$1"' > ./start.sh \
  && chmod +x ./start.sh

# Set environment variables
ENV HOST=0.0.0.0
ENV PORT=8080

# Expose the port the server will run on
EXPOSE $PORT

# Run the server
CMD ["./start.sh", "run"]
