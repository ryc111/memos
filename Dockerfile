# Stage 1: Builder
# Use a Go image and install all necessary build dependencies.
FROM golang:1.21-alpine AS builder

# Install build-base for CGO, git, Node.js, and npm.
RUN apk add --no-cache build-base git nodejs npm

# Install pnpm for frontend dependency management.
RUN npm install -g pnpm

# Install buf for protocol buffer generation.
RUN GOBIN=/usr/local/bin go install github.com/bufbuild/buf/cmd/buf@v1.33.0

# Set the working directory.
WORKDIR /app

# --- Frontend Dependencies ---
# Copy dependency definitions and install them first to leverage Docker cache.
COPY web/package.json web/pnpm-lock.yaml ./web/
RUN pnpm --dir web install --frozen-lockfile

# --- Backend Dependencies ---
# Copy dependency definitions and download them.
COPY go.mod go.sum ./
RUN go mod download

# --- Source Code ---
# Copy the entire project source code into the builder.
COPY . .

# --- Build Frontend ---
# The 'release' script builds the frontend and places assets in the Go server's expected directory.
RUN pnpm --dir web release

# --- Generate Protobuf Code ---
# Generate Go and TypeScript code from .proto files.
RUN buf generate proto

# --- Build Backend ---
# Build the final Go binary. It's statically linked, making it portable.
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /memos ./cmd/memos

# Stage 2: Final Runtime Image
# Use a minimal alpine image for a small footprint.
FROM alpine:latest

# Set timezone to UTC.
RUN apk add --no-cache tzdata
ENV TZ="UTC"

# Set the working directory for the application.
WORKDIR /usr/local/memos/

# Copy the compiled Go binary from the builder stage.
COPY --from=builder /memos /usr/local/memos/

# Copy the official entrypoint script.
COPY ./scripts/entrypoint.sh /usr/local/memos/

# Create the data directory and set permissions. This will be the mount point for the volume.
RUN mkdir -p /var/opt/memos && chmod 777 /var/opt/memos
VOLUME /var/opt/memos

# Expose the default memos port.
EXPOSE 5230

# Set default environment variables for production mode.
ENV MEMOS_MODE="prod"
ENV MEMOS_PORT="5230"

# Set the entrypoint to the script, which will prepare and run the application.
ENTRYPOINT ["./entrypoint.sh"]
CMD ["./memos"]
