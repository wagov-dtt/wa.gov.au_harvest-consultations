FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim@sha256:096c3761e41782bdb2818381a8202153d39e0618a9e12c757a2c46327c1aa83c

LABEL org.opencontainers.image.source=https://github.com/wagov-dtt/wa.gov.au_harvest-consultations
LABEL org.opencontainers.image.description="Harvest consultations with sqlmesh"
LABEL org.opencontainers.image.licenses=Apache-2.0

# Copy the project into the image
ADD . /app

# Sync the project into a new environment, using the frozen lockfile
WORKDIR /app
RUN ["uv", "sync", "--frozen"]

ENV PATH="/app/.venv/bin:$PATH"

CMD ["sqlmesh", "ui"]