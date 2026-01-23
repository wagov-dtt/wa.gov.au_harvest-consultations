set dotenv-load

image := "harvest-consultations"
registry := "ghcr.io/wagov-dtt"

# List commands
default:
  @just --list

# Run pytest (fast)
test:
  uv run pytest test_harvest.py -v

# Build image, run with MariaDB, show results (slow)
test-full: _build _mysql
  docker run --rm --network host --env-file .env \
    -e MYSQL_DUCKDB_PATH="host=127.0.0.1 user=root" {{image}}:test
  docker run --rm --network host --env-file .env --entrypoint python \
    -e MYSQL_DUCKDB_PATH="host=127.0.0.1 user=root" {{image}}:test -m harvest stats

# Build and push multi-platform image
publish: _buildkit
  BUILDKIT_HOST=docker-container://buildkit railpack build . \
    --name {{registry}}/{{image}}:latest --platform linux/amd64,linux/arm64 --push

# Stop services
clean:
  -docker stop harvest-mysql buildkit 2>/dev/null
  -docker rm harvest-mysql buildkit 2>/dev/null

_buildkit:
  @docker start buildkit 2>/dev/null || docker run -d --name buildkit --privileged moby/buildkit

_build: _buildkit
  BUILDKIT_HOST=docker-container://buildkit railpack build . --name {{image}}:test

_mysql:
  @docker start harvest-mysql 2>/dev/null || docker run -d --name harvest-mysql \
    -e MARIADB_ROOT_PASSWORD=${MYSQL_PWD:-secret} -p 3306:3306 mariadb:11
  @until docker exec harvest-mysql mariadb -uroot -p${MYSQL_PWD:-secret} -e "SELECT 1" >/dev/null 2>&1; do sleep 1; done
