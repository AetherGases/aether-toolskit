import pytest
from pathlib import Path

from aether_env.config import (
    ConfigError,
    SecretConfigError,
    application_secret_data,
    load_settings,
    read_dotenv,
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
        "GEMINI_API_KEY": "",
        "POSTGRES_HOST": "localhost",
    }


def test_read_dotenv_strips_single_quoted_values(tmp_path: Path):
    path = tmp_path / ".env"
    path.write_text("APP_NAME='aeko-hub'\nMSG='it\\'s fine'\n", encoding="utf-8")
    data = read_dotenv(path)
    assert data["APP_NAME"] == "aeko-hub"
    assert data["MSG"] == "it's fine"


def test_missing_required_key_lists_only_the_name():
    env = _env()
    env["JWT_SECRET"] = "  "
    with pytest.raises(ConfigError) as caught:
        load_settings(env)
    assert caught.value.missing == ("JWT_SECRET",)


def test_secret_ignores_os_environ_noise_when_app_env_is_dotenv():
    env = _env()
    env["CommonProgramFiles(x86)"] = "C:\\Program Files (x86)\\Common Files"
    env["PATH"] = "/usr/bin:" + "x" * 5000
    dotenv = _env()
    settings = load_settings(env, app_env=dotenv)
    data = application_secret_data(settings)
    assert "PATH" not in data
    assert "CommonProgramFiles(x86)" not in data


def test_invalid_secret_key_in_dotenv_raises():
    dotenv = _env()
    dotenv["BAD KEY"] = "nope"
    settings = load_settings(_env(), app_env=dotenv)
    with pytest.raises(SecretConfigError):
        application_secret_data(settings)


def test_defaults_and_secret_rewrite_hosts():
    settings = load_settings(_env())
    assert settings.node_type == "t3.medium"
    assert settings.node_count == 1
    assert settings.cluster_role_arn is None
    data = application_secret_data(settings)
    assert "AWS_SECRET_ACCESS_KEY" not in data
    assert data["POSTGRES_HOST"] == "postgres"
    assert data["POSTGRES_PORT"] == "5432"
    assert data["API_PORT"] == "8080"
    assert data["SERVER_PORT"] == "8080"
    assert data["PORT"] == "8000"
    assert data["DATABASE_A_URL"] == "postgresql://sa:p%40ss@postgres:5432/dbAether1Year"
    assert data["DATABASE_B_URL"].endswith("/dbAether2Year")
    assert data["MONGO_URI"].startswith("mongodb://mongo:mp@mongo:27017/dbAether")
    assert data["REDIS_URI"] == "redis://:rp@redis:6379/0"
    assert data["GEMINI_API_KEY"] == ""
