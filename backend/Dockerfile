# ---- stage 1: build wheels ----
FROM python:3.8-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc libc6-dev libpq-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# ---- stage 2: runtime ----
FROM python:3.8-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 curl postgresql-client && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --uid 1000 appuser

WORKDIR /app
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir /wheels/* && rm -rf /wheels

COPY --chown=appuser:appuser . .
USER appuser

ENV PYTHONPATH=. PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

# Which commit this image is, served at /api/v1/version and stamped as OCI
# labels (docs/ARCHITECTURE.md §20.2). A git SHA is not a secret, so a build
# arg is fine here. Declared this late so a new SHA only invalidates the layers
# below -- the dependency layers above stay cached.
#   docker build --build-arg GIT_SHA=$(git rev-parse HEAD) \
#                --build-arg BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ) ./backend
ARG GIT_SHA=unknown
ARG BUILD_TIME=unknown
ENV GIT_SHA=${GIT_SHA} BUILD_TIME=${BUILD_TIME}
LABEL org.opencontainers.image.revision=${GIT_SHA} \
      org.opencontainers.image.created=${BUILD_TIME}

EXPOSE 8888

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -fsS http://localhost:8888/api/v1/health/live || exit 1

CMD ["gunicorn", "app.main:app", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--workers", "4", "--bind", "0.0.0.0:8888", \
     "--access-logfile", "-", "--error-logfile", "-"]
