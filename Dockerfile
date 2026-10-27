# syntax=docker/dockerfile:1
FROM ghcr.io/astral-sh/uv:0.12.23 AS uv
FROM python:3.12-slim
COPY --from=uv /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN --mount=type=secret,id=proxy_ca \
    if [ -f /run/secrets/proxy_ca ]; then export SSL_CERT_FILE=/run/secrets/proxy_ca; fi; \
    uv sync --frozen --no-dev --no-install-project
COPY carguy ./carguy
RUN useradd --uid 10001 --create-home app \
    && chmod -R a+rX /app/carguy \
    && mkdir /app/.data && chown app:app /app/.data
USER app
ENV CARGUY_ENV=production CARGUY_STORE=firestore
EXPOSE 8080
CMD ["sh", "-c", "exec /app/.venv/bin/python -m uvicorn carguy.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
