FROM rust:1-bookworm AS build
WORKDIR /build/backend
COPY backend/Cargo.toml backend/Cargo.lock backend/build.rs ./
COPY backend/src ./src
COPY backend/migrations ./migrations
RUN cargo build --locked --release -j 2

FROM python:3.12-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends nginx-light ca-certificates libgomp1 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /srv/supra
COPY ml/requirements.txt ml/requirements.txt
RUN python -m pip install --no-cache-dir --only-binary=:all: -r ml/requirements.txt
COPY ml/*.py ml/
COPY ml/artifacts/forecast.pt ml/artifacts/model_card.json ml/artifacts/weather_model.json ml/artifacts/
COPY file_gtfs/ file_gtfs/
COPY --from=build /build/backend/target/release/supra_backend /usr/local/bin/
COPY deploy/render/start.sh deploy/render/nginx.conf ./
ENV TRANSJAKARTA_GTFS_DIR=/srv/supra/file_gtfs \
    AVATAR_STORAGE_DIR=/tmp/supra-avatars \
    INTELLIGENCE_URL=http://127.0.0.1:8001 \
    PYTHONDONTWRITEBYTECODE=1 \
    OPENBLAS_NUM_THREADS=1 \
    MALLOC_ARENA_MAX=2
USER 65534:65534
RUN cd ml && python -c 'from weather_model import load; load(); from inference import Forecaster; f = Forecaster(); f.load(); print(f.state["card"]["model_id"])'
EXPOSE 10000
CMD ["bash", "/srv/supra/start.sh"]
