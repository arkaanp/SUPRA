# Multi-stage Dockerfile for deploying SUPRA (Rust Axum API + Python PyTorch/RSS service) to Render.

# Stage 1: Build the Rust backend binary (Rust 1.x latest supports edition 2024 & Cargo.lock v4).
FROM rust:1-slim-bookworm AS builder
WORKDIR /app/backend

RUN apt-get update \
    && apt-get install -y --no-install-recommends pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/*

COPY backend/ ./
RUN cargo build --release --locked

# Stage 2: Runtime image with Python ML/RSS service + compiled Rust API server.
FROM python:3.12-slim-bookworm
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Install CPU-only PyTorch and ML dependencies, then train baseline forecast weights.
COPY ml/requirements.txt ./ml/requirements.txt
RUN pip install --no-cache-dir -r ml/requirements.txt

COPY ml/ ./ml/
# Allow build to succeed even if public Open-Meteo/CAMS APIs throttle during build;
# ml/serve.py will still run ANTARA RSS news and report forecast unavailable cleanly.
RUN python ml/train.py --days 60 --epochs 100 || echo "Warning: initial ML training skipped/failed during build"

# Copy static TransJakarta GTFS feed and compiled Axum binary.
COPY file_gtfs/ ./file_gtfs/
COPY --from=builder /app/backend/target/release/supra_backend /usr/local/bin/supra_backend

RUN mkdir -p /app/uploads/avatars

ENV TRANSJAKARTA_GTFS_DIR=/app/file_gtfs \
    INTELLIGENCE_URL=http://127.0.0.1:8001 \
    AVATAR_STORAGE_DIR=/app/uploads/avatars \
    PORT=3000

EXPOSE 3000

# Start loopback Python ML/RSS service, apply idempotent SQLx migrations, then launch Axum.
CMD ["sh", "-c", "python ml/serve.py & supra_backend migrate && exec supra_backend"]
