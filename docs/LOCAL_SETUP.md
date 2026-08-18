# Local setup and reproducibility

## Supported developer environment

The portable path requires:

- Git 2.x
- Docker Desktop or Docker Engine with the `docker compose` v2 plugin
- Bash (built in on macOS/Linux; use WSL2 on Windows)
- `curl`
- at least 6 GB of memory available to Docker and about 5 GB of free disk space
- ports 3000, 8080, and 5432 available, unless the existing Creator Link Store containers already own them

Node.js, Java, Maven, and PostgreSQL do not need to be installed on the host for the container workflow. Their versions live in the Dockerfiles and Compose file.

## One-command bootstrap

Start with only the infrastructure repository:

```bash
mkdir creator-store-workspace
cd creator-store-workspace
git clone https://github.com/kvsram/creator-link-store-infrastructure.git infrastructure
cd infrastructure
./scripts/bootstrap-local.sh
```

Expected sibling layout after bootstrap:

```text
creator-store-workspace/
├── frontend/
├── backend/
└── infrastructure/
```

Do not rename those folders unless you also update `local/docker-compose.yml`; its build contexts intentionally reference `../../frontend` and `../../backend`.

## What startup does

1. Validates Git, Docker, Compose v2, `curl`, the Docker daemon, sibling folders, and required build files.
2. Builds the frontend image with Node.js 24 and NGINX.
3. Builds the backend image with Maven and Java 17.
4. Starts PostgreSQL 16 and waits for `pg_isready`.
5. Starts Spring Boot, applies the idempotent schema, and seeds demo data only when `creators` is empty.
6. Starts the frontend after API health succeeds.
7. Tests health, the public store, dashboard, INR, disabled external integrations, disabled checkout safety, and SPA delivery.

Success ends with URLs for the admin, public store, and health endpoint.

## Manual startup

```bash
cd creator-store-workspace/infrastructure
./scripts/doctor.sh
docker compose -f local/docker-compose.yml up -d --build
./scripts/smoke-test.sh
```

Useful inspection commands:

```bash
docker compose -f local/docker-compose.yml ps
docker compose -f local/docker-compose.yml logs -f --tail=200
docker compose -f local/docker-compose.yml config
```

Stop without deleting data:

```bash
docker compose -f local/docker-compose.yml down
```

The named `creator-store-data` volume preserves PostgreSQL rows across rebuilds and restarts. Removing volumes is intentionally omitted because it destroys local data. If a clean database is truly required, first export anything needed, then have the operator explicitly choose the destructive Compose volume-removal command.

## External integration test mode

Fresh clones use:

```text
PAYMENTS_MODE=disabled
INSTAGRAM_MODE=disabled
```

For provider sandbox testing:

```bash
cp local/.env.example local/.env
```

Add test credentials to `local/.env`, change only the required mode from `disabled` to `test`, and rebuild the API. The smoke script does not source `.env` because shell-sourcing an environment file is unsafe; tell it the expected non-default modes explicitly:

```bash
EXPECTED_PAYMENTS_MODE=test EXPECTED_INSTAGRAM_MODE=test ./scripts/smoke-test.sh
```

In test/live payment mode the general smoke suite deliberately skips checkout creation because that call has an external side effect. Follow the signed provider-sandbox cases in the integration guide. `local/.env` is ignored by Git. A mode of `live` can affect real accounts and must not be used as a casual local test setting.

## Independent developer loops

The container workflow is the reproducibility contract. For faster local editing, install Node.js 24 and Java 17/Maven, keep PostgreSQL running, then follow the frontend and backend READMEs. Verify the container path again before pushing.

## Troubleshooting

### Docker engine is not reachable

Start Docker Desktop (macOS/Windows) or `dockerd` (Linux), wait until it reports healthy, and run `make doctor` again.

### A port is already allocated

Use `docker compose -f local/docker-compose.yml ps` and `lsof -nP -iTCP:<port> -sTCP:LISTEN` to find the owner. Do not kill an unrelated process automatically. Stop it intentionally or change the published port in the Compose file.

### API never becomes healthy

Run:

```bash
docker compose -f local/docker-compose.yml logs --tail=250 creator-store-api database
```

Typical causes are an unhealthy database, an old incompatible local volume, insufficient Docker memory, or a failed dependency download during image build.

### Frontend loads but API calls fail

Confirm `http://localhost:8080/health` works, inspect `creator-store-api` logs, and verify the NGINX proxy configuration in the frontend repository. In the container path, browser `/api` requests are proxied to the backend service; CORS is not the normal path.

### Another laptop produces different demo IDs

The documented `alex` creator ID of `1` is guaranteed only for a clean database. Existing volumes preserve previous rows. Functional URLs and API semantics remain the contract; hard-coded IDs are test fixtures, not production identity design.

### Apple Silicon or x86 laptop

The selected upstream images are multi-architecture. Docker will pull/build for the host architecture. If a provider dependency later introduces an architecture-specific image, pin and document an explicit platform rather than relying on emulation silently.

## Reproducibility evidence to capture

When handing the workspace to another laptop or AI, capture:

```bash
git -C ../frontend rev-parse HEAD
git -C ../backend rev-parse HEAD
git rev-parse HEAD
docker compose -f local/docker-compose.yml config --no-interpolate
./scripts/smoke-test.sh
```

Those three Git SHAs plus the rendered Compose model identify exactly what was tested. `--no-interpolate` prevents provider secrets from being printed if `local/.env` exists.
