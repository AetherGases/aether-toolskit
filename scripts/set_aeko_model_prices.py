"""Upsert AEKO_MODEL_PRICES into a dotenv file for campaign-specific USD rates."""

from argparse import ArgumentParser
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from aether_env.model_prices import KEY, upsert_dotenv


def main() -> int:
    parser = ArgumentParser(description="Write AEKO_MODEL_PRICES into a .env file.")
    parser.add_argument(
        "--path",
        type=Path,
        default=ROOT / ".env",
        help="Dotenv file to update (default: toolkit .env).",
    )
    args = parser.parse_args()
    upsert_dotenv(args.path)
    print(f"Wrote {KEY} to {args.path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
