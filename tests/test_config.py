import pytest
from pathlib import Path

from aether_env.config import (
    ConfigError,
    SecretConfigError,
    application_secret_data,
    application_secret_fingerprint,
    load_settings,
    read_dotenv,
)


def _env():
    return {
        "AWS_ACCESS_KEY_ID": "aki",
        "AWS_SECRET_ACCESS_KEY": "secret",
        "AWS_REGION": "sa-east-1",
        "POSTGRES_HOST": "pg.example.com",
        "POSTGRES_PORT": "5432",
        "POSTGRES_USER": "sa",
        "POSTGRES_PASSWORD": "p@ss",
        "POSTGRES_DB_FIRST_YEAR": "dbAether1Year",
        "POSTGRES_DB_SECOND_YEAR": "dbAether2Year",
        "POSTGRES_SSLMODE": "require",
        "MONGO_HOST": "mongo.example.com",
        "MONGO_PORT": "27017",
        "MONGO_USER": "mongo",
        "MONGO_PASSWORD": "mp",
        "MONGO_DB": "dbAether",
        "REDIS_HOST": "redis.example.com",
        "REDIS_PORT": "6379",
        "REDIS_PASSWORD": "rp",
        "JWT_SECRET": "jwt",
        "OAUTH_ISSUER": "https://aethergases.org/hub",
        "OAUTH_AUDIENCE": "https://aethergases.org/hub/aether-api/v1/mcp/",
        "GEMINI_API_KEY": "",
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


def test_defaults_and_secret_builds_external_database_urls():
    settings = load_settings(_env())
    assert settings.node_type == "t3.medium"
    assert settings.node_count == 1
    assert settings.cluster_role_arn is None
    data = application_secret_data(settings)
    assert "AWS_SECRET_ACCESS_KEY" not in data
    assert data["POSTGRES_HOST"] == "pg.example.com"
    assert data["POSTGRES_PORT"] == "5432"
    assert data["API_PORT"] == "8080"
    assert data["SERVER_PORT"] == "8080"
    assert data["PORT"] == "8000"
    assert (
        data["DATABASE_A_URL"]
        == "postgresql://sa:p%40ss@pg.example.com:5432/dbAether1Year?sslmode=require"
    )
    assert data["DATABASE_B_URL"].endswith("/dbAether2Year?sslmode=require")
    assert data["DB_URL"] == "jdbc:postgresql://pg.example.com:5432/dbAether2Year?sslmode=require"
    assert data["MONGO_URI"].startswith("mongodb://mongo:mp@mongo.example.com:27017/dbAether")
    assert data["REDIS_URI"] == "redis://:rp@redis.example.com:6379/0"
    assert data["GEMINI_API_KEY"] == ""
    assert data["OAUTH_ISSUER"] == "https://aethergases.org/hub"
    assert data["OAUTH_AUDIENCE"] == "https://aethergases.org/hub/aether-api/v1/mcp/"
    assert data["AUTH_MS_BASE_URL"] == "http://aether-ms-auth:8080"
    assert "PROFILE_MS_BASE_URL" not in data


def test_secret_fingerprint_changes_when_env_value_changes():
    settings = load_settings(_env())
    first = application_secret_fingerprint(application_secret_data(settings))
    dotenv = _env()
    dotenv["JWT_SECRET"] = "jwt-rotated"
    second = application_secret_fingerprint(application_secret_data(load_settings(_env(), app_env=dotenv)))
    assert first != second


def test_explicit_mongo_uri_is_preserved():
    dotenv = _env()
    dotenv["MONGO_URI"] = "mongodb+srv://user:secret@cluster.example.net/dbAether"
    settings = load_settings(_env(), app_env=dotenv)
    data = application_secret_data(settings)
    assert data["MONGO_URI"] == "mongodb+srv://user:secret@cluster.example.net/dbAether"
    assert data["MONGO_URL"] == data["MONGO_URI"]


def test_profile_ms_base_url_stripped_from_secret():
    dotenv = _env()
    dotenv["PROFILE_MS_BASE_URL"] = "http://legacy-profile:8080"
    settings = load_settings(_env(), app_env=dotenv)
    data = application_secret_data(settings)
    assert "PROFILE_MS_BASE_URL" not in data
    assert data["AUTH_MS_BASE_URL"] == "http://aether-ms-auth:8080"
