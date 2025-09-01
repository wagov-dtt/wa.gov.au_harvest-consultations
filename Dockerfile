FROM ghcr.io/astral-sh/uv:trixie-slim

# Copy the project into the image
ADD . /app

# Sync the project into a new environment, using the frozen lockfile
WORKDIR /app

# Switch to a non root user
RUN useradd -u 1000 -m appuser && chown appuser:appuser -R .
USER 1000

RUN ["uv", "sync", "--frozen"]

ENV PATH="/app/.venv/bin:$PATH"

CMD ["sqlmesh", "ui"]
