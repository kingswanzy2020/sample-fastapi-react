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

EXPOSE 8888

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -fsS http://localhost:8888/api/v1 || exit 1

CMD ["gunicorn", "app.main:app", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--workers", "4", "--bind", "0.0.0.0:8888", \
     "--access-logfile", "-", "--error-logfile", "-"]
