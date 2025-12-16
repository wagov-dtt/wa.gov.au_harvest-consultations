set dotenv-load

image := "harvest-consultations"
registry := "ghcr.io/wagov-dtt"

# Choose a task to run
default:
  just --choose

# ============================================================================
# LOCAL DEVELOPMENT
# ============================================================================

# Build image with railpack
build:
  @docker ps -a --filter "name=buildkit" 2>/dev/null | grep -q buildkit || \
    (echo "Starting BuildKit daemon..." && \
     docker run --rm --privileged -d --name buildkit moby/buildkit > /dev/null && \
     sleep 2)
  BUILDKIT_HOST='docker-container://buildkit' railpack build . --name {{image}}:test --config-file railpack.json

# Start local Percona MySQL
mysql:
  @docker ps -a --filter "name=harvest-mysql" 2>/dev/null | grep -q harvest-mysql && \
    (echo "MySQL already running" && docker start harvest-mysql 2>/dev/null) || \
    (echo "Starting Percona MySQL..." && \
     docker run --rm -d \
       --name harvest-mysql \
       -e MYSQL_ROOT_PASSWORD={{env("MYSQL_PWD", "secret")}} \
       -p 3306:3306 \
       percona:latest \
       --default-authentication-plugin=mysql_native_password && \
     echo "✓ MySQL ready on localhost:3306")

# Stop local MySQL
mysql-stop:
  docker stop harvest-mysql 2>/dev/null || echo "MySQL not running"

# Test container locally with local MySQL (uses .env for config)
test: build mysql
  @echo "Running container against local MySQL (with .env config)..."
  docker run --rm \
    --network host \
    --env-file .env \
    -e MYSQL_DUCKDB_PATH="host=127.0.0.1 user=root" \
    {{image}}:test

# ============================================================================
# PRODUCTION
# ============================================================================

# Build and publish multi-platform image
publish:
  @docker ps -a --filter "name=buildkit" 2>/dev/null | grep -q buildkit || \
    (echo "Starting BuildKit daemon..." && \
     docker run --rm --privileged -d --name buildkit moby/buildkit > /dev/null && \
     sleep 2)
  BUILDKIT_HOST='docker-container://buildkit' railpack build . --name {{registry}}/{{image}}:latest --platform linux/amd64 --platform linux/arm64 --config-file railpack.json

# ============================================================================
# CLEANUP
# ============================================================================

# Stop all local services
clean: mysql-stop
  @echo "✓ Cleaned up local environment"
