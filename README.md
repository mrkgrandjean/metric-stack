# metric-stack

Orchestration/deployment layer for a personal home metrics system. This repo
declares which services run, how they're configured, and how they're
scheduled — it contains **no application code**.

Every service here is either an upstream image (`postgres`, `grafana`,
`ofelia`) or a custom image built and pushed by its own repo's CI to GHCR
(`aggregator`, and each collector). This repo never builds those images; it
only references them. The one exception is `dead-mans-switch`, a small
operational script that's stack-owned tooling rather than a product with its
own repo, so it's built locally from `scripts/`.

Postgres schema and migrations live in and are applied by the aggregator's
image on startup — this repo has zero knowledge of what tables exist beyond
what the Grafana dashboard queries assume (`metrics`, `collector_runs`).

Runs via Docker Compose, targeting a Windows machine under WSL2 + Docker
Desktop.

## One-time setup

The `aggregator` and collector images are private GHCR packages, so you need
to authenticate before `docker compose pull` will work:

```
docker login ghcr.io -u <your-github-username>
# password: a GitHub PAT with `read:packages` scope
```

Then copy the env template and fill in real values:

```
cp .env.example .env
```

## Bringing the stack up

```
docker compose up -d
```

Check status:

```
docker compose ps
```

## Updating a single service

Pull the new image and recreate just that service — no rebuild needed, the
image already exists in GHCR:

```
docker compose pull <service>
docker compose up -d <service>
```

## Adding a new collector

1. Add a service block to `docker-compose.yml` following the pattern of the
   existing collectors (e.g. `xbox-time-collector`): `image:` pointing at the
   collector's GHCR package, `AGGREGATOR_URL` pointing at `aggregator`, and
   `ofelia.*` labels setting its schedule.
2. `docker compose up -d`

No rebuild is needed — collectors are one-shot jobs run by Ofelia on their
label-defined schedule, not long-running containers.

## Where to look when something's broken

- **Service logs:** `docker compose logs -f <service>` (e.g. `aggregator`,
  `postgres`, `ofelia`, or a specific collector).
- **Collector health:** the `collector_runs` table, or the "Collector runs
  health" panel on the Grafana "Metrics Overview" dashboard
  (`http://localhost:3000`).
- **Missed-collector alerts:** the `dead-mans-switch` job runs daily via
  Ofelia and pushes a notification to the configured ntfy.sh topic
  (`NTFY_TOPIC` in `.env`) for any collector overdue past its
  `expected_interval_minutes` plus grace buffer. Subscribe to that topic in
  the ntfy app/web client to receive alerts.
- **Ofelia scheduling issues:** `docker compose logs -f ofelia` shows each
  job's next run and execution output.

## Repo structure

```
metric-stack/
  docker-compose.yml
  .env.example
  dashboards/
    grafana/
      provisioning/
        datasources/
        dashboards/
  scripts/
    dead_mans_switch.py
    dead_mans_switch.Dockerfile
  README.md
```
