FROM ghcr.io/astral-sh/uv:debian

# Copy the project into the image
ADD . /app

# Sync the project into a new environment, using the frozen lockfile
WORKDIR /app
RUN uv sync --frozen

CMD ["sqlmesh", "ui"]