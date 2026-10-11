"""Verify AEKO_MODEL_PRICES dotenv upsert and Kubernetes secret passthrough."""

from pathlib import Path

from aether_env.config import application_secret_data, load_settings
from aether_env.model_prices import (
    DEFAULT_PRICES,
    KEY,
    dump_env_value,
    upsert_dotenv,
)


def _env():
    return {
        "AWS_ACCESS_KEY_ID": "aki",
        "AWS_SECRET_ACCESS_KEY": "secret",
        "AWS_REGION": "sa-east-1",
        "POSTGRES_USER": "sa",
        "POSTGRES_PASSWORD": "p@ss",
        "POSTGRES_DB_FIRST_YEAR": "dbAether1Year",
        "POSTGRES_DB_SECOND_YEAR": "dbAether2Year",
        "MONGO_USER": "mongo",
        "MONGO_PASSWORD": "mp",
        "MONGO_DB": "dbAether",
        "REDIS_PASSWORD": "rp",
        "JWT_SECRET": "jwt",
        "OAUTH_ISSUER": "https://aethergases.org/hub",
        "OAUTH_AUDIENCE": "https://aethergases.org/hub/aether-api/v1/mcp/",
    }


def test_dump_env_value_is_single_quoted_json():
    assert dump_env_value({"m": {"input_per_million": 1.0, "output_per_million": 2.0}}) == (
        '\'{"m": {"input_per_million": 1.0, "output_per_million": 2.0}}\''
    )


def test_upsert_appends_aeko_model_prices(tmp_path: Path):
    path = tmp_path / ".env"
    path.write_text("GEMINI_API_KEY=k\n", encoding="utf-8")
    upsert_dotenv(path)
    text = path.read_text(encoding="utf-8")
    assert text.startswith("GEMINI_API_KEY=k\n")
    assert f"{KEY}={dump_env_value(DEFAULT_PRICES)}" in text


def test_upsert_replaces_an_existing_value(tmp_path: Path):
    path = tmp_path / ".env"
    path.write_text(f"{KEY}='{{}}'\nGEMINI_API_KEY=k\n", encoding="utf-8")
    upsert_dotenv(path, {"flash": {"input_per_million": 0.1, "output_per_million": 0.2}})
    lines = path.read_text(encoding="utf-8").splitlines()
    assert lines[0] == f"{KEY}={dump_env_value({'flash': {'input_per_million': 0.1, 'output_per_million': 0.2}})}"
    assert lines[1] == "GEMINI_API_KEY=k"


def test_secret_keeps_quoted_json_from_dotenv():
    dotenv = _env()
    dotenv[KEY] = dump_env_value(DEFAULT_PRICES).strip("'")
    settings = load_settings(_env(), app_env=dotenv)
    data = application_secret_data(settings)
    assert data[KEY] == dump_env_value(DEFAULT_PRICES).strip("'")
