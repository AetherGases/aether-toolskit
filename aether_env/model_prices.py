"""Format and upsert AEKO_MODEL_PRICES in dotenv files.

Environment rates are more effective than hardcoded prices because they
allow campaigns with custom pricing.
"""

from __future__ import annotations

import json
from pathlib import Path

KEY = "AEKO_MODEL_PRICES"

DEFAULT_PRICES = {
    "gemini-3.5-flash": {"input_per_million": 0.15, "output_per_million": 0.60},
    "gemini-3.1-flash-lite": {"input_per_million": 0.025, "output_per_million": 0.15},
}


def dump_env_value(prices: dict) -> str:
    """Return the single-quoted JSON dotenv value for a price table."""

    return "'" + json.dumps(prices) + "'"


def upsert_dotenv(path: Path, prices: dict | None = None) -> None:
    """Write or replace AEKO_MODEL_PRICES in a dotenv file, leaving other keys intact."""

    table = DEFAULT_PRICES if prices is None else prices
    assignment = f"{KEY}={dump_env_value(table)}"
    if not path.exists():
        path.write_text(assignment + "\n", encoding="utf-8")
        return
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    replaced = False
    out: list[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith(f"{KEY}="):
            newline = "\n" if line.endswith("\n") else ""
            out.append(assignment + newline)
            replaced = True
        else:
            out.append(line)
    if not replaced:
        if out and not out[-1].endswith("\n"):
            out[-1] = out[-1] + "\n"
        out.append(assignment + "\n")
    path.write_text("".join(out), encoding="utf-8")
