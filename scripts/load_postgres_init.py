"""Apply init-postgres SQL to the Postgres instance configured in .env."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from aether_env.config import read_dotenv
INIT_DIR = ROOT / "init-postgres"

# Same order as Kubernetes init ConfigMap (lexicographic), with explicit target DBs.
STEPS: tuple[tuple[str, str], ...] = (
    ("01-creating-databases.sql", "defaultdb"),
    ("02-creating-initial-tables-second-year.sql", "dbAether2Year"),
    ("03-second-year-audit-and-logs.sql", "dbAether2Year"),
    ("04-second-year-functions-and-procedures.sql", "dbAether2Year"),
    ("05-second-year-analytical-layer.sql", "dbAether2Year"),
    ("06-second-year-indexes.sql", "dbAether2Year"),
    ("07-second-year-metadata-catalog.sql", "dbAether2Year"),
    ("08-first-year-creating-initial-tables.sql", "dbAether1Year"),
    ("200-adding-users-initial.sql", "dbAether2Year"),
)


def _connection_uri(env: dict[str, str], database: str) -> str:
    user = quote(env["POSTGRES_USER"], safe="")
    password = quote(env["POSTGRES_PASSWORD"], safe="")
    host = env["POSTGRES_HOST"].strip()
    port = env["POSTGRES_PORT"].strip()
    sslmode = env.get("POSTGRES_SSLMODE", "require").strip() or "require"
    return f"postgresql://{user}:{password}@{host}:{port}/{database}?sslmode={quote(sslmode, safe='')}"


def _run_psql(env: dict[str, str], database: str, *, file_name: str | None = None, sql: str | None = None) -> None:
    uri = _connection_uri(env, database)
    cmd = [
        "docker",
        "run",
        "--rm",
        "-v",
        f"{INIT_DIR}:/init:ro",
        "postgres:16.10",
        "psql",
        uri,
        "-v",
        "ON_ERROR_STOP=1",
    ]
    if file_name:
        cmd.extend(["-f", f"/init/{file_name}"])
    if sql:
        cmd.extend(["-c", sql])
    label = file_name or "SQL"
    print(f"Running {label} on {database} ...", flush=True)
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode != 0:
        combined = f"{result.stdout}\n{result.stderr}"
        if "already exists" in combined or "duplicate key value" in combined:
            print(f"  (skipped: already exists)")
            return
        if result.stdout:
            print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
        raise SystemExit(result.returncode)
    if result.stdout:
        print(result.stdout, end="")


def main() -> int:
    env = read_dotenv(ROOT / ".env")
    required = (
        "POSTGRES_HOST",
        "POSTGRES_PORT",
        "POSTGRES_USER",
        "POSTGRES_PASSWORD",
    )
    missing = [key for key in required if not env.get(key, "").strip()]
    if missing:
        print("Missing in .env: " + ", ".join(missing), file=sys.stderr)
        return 2

    for db_name in ("dbAether1Year", "dbAether2Year"):
        _run_psql(env, "defaultdb", sql=f'CREATE DATABASE "{db_name}"')

    for file_name, database in STEPS:
        path = INIT_DIR / file_name
        if not path.exists():
            print(f"Missing {path}", file=sys.stderr)
            return 2
        if file_name == "01-creating-databases.sql":
            continue
        _run_psql(env, database, file_name=file_name)

    print("Postgres init finished.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
