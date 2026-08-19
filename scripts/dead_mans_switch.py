#!/usr/bin/env python3
"""Alerts via ntfy.sh when any collector hasn't run within its expected interval + grace buffer."""

import os
import sys
from datetime import datetime, timedelta, timezone

import psycopg2
import requests

POSTGRES_HOST = os.environ.get("POSTGRES_HOST", "postgres")
POSTGRES_PORT = os.environ.get("POSTGRES_PORT", "5432")
POSTGRES_DB = os.environ["POSTGRES_DB"]
POSTGRES_USER = os.environ["POSTGRES_USER"]
POSTGRES_PASSWORD = os.environ["POSTGRES_PASSWORD"]

GRACE_MINUTES = int(os.environ.get("DEAD_MANS_SWITCH_GRACE_MINUTES", "30"))

NTFY_URL = os.environ.get("NTFY_URL", "https://ntfy.sh")
NTFY_TOPIC = os.environ["NTFY_TOPIC"]

QUERY = """
    SELECT DISTINCT ON (collector_name)
        collector_name,
        started_at,
        expected_interval_minutes
    FROM collector_runs
    ORDER BY collector_name, started_at DESC
"""


def find_overdue_collectors(conn):
    overdue = []
    now = datetime.now(timezone.utc)
    with conn.cursor() as cur:
        cur.execute(QUERY)
        for collector_name, started_at, expected_interval_minutes in cur.fetchall():
            deadline = started_at + timedelta(
                minutes=expected_interval_minutes + GRACE_MINUTES
            )
            if now > deadline:
                overdue.append((collector_name, started_at))
    return overdue


def notify(overdue):
    lines = [
        f"- {name}: last ran at {started_at.isoformat()}"
        for name, started_at in overdue
    ]
    message = "Overdue collectors:\n" + "\n".join(lines)
    response = requests.post(
        f"{NTFY_URL.rstrip('/')}/{NTFY_TOPIC}",
        data=message.encode("utf-8"),
        headers={"Title": "Metric stack: dead man's switch"},
        timeout=10,
    )
    response.raise_for_status()


def main():
    conn = psycopg2.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        dbname=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
    )
    try:
        overdue = find_overdue_collectors(conn)
    finally:
        conn.close()

    if overdue:
        notify(overdue)
        print(f"Found {len(overdue)} overdue collector(s), notified via ntfy.")
    else:
        print("All collectors within their expected interval.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"dead_mans_switch failed: {exc}", file=sys.stderr)
        sys.exit(1)
