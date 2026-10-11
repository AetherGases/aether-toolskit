import hashlib
import re
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote


REQUIRED = (
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_REGION",
    "POSTGRES_HOST",
    "POSTGRES_PORT",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "POSTGRES_DB_FIRST_YEAR",
    "POSTGRES_DB_SECOND_YEAR",
    "MONGO_HOST",
    "MONGO_PORT",
    "MONGO_USER",
    "MONGO_PASSWORD",
    "MONGO_DB",
    "REDIS_HOST",
    "REDIS_PORT",
    "REDIS_PASSWORD",
    "JWT_SECRET",
    "OAUTH_ISSUER",
    "OAUTH_AUDIENCE",
)

EXCLUDED_FROM_SECRET = frozenset({
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN",
    "AWS_REGION",
    "EKS_NODE_TYPE",
    "EKS_NODE_COUNT",
    "EKS_CLUSTER_ROLE_ARN",
    "EKS_NODE_ROLE_ARN",
})

SECRET_KEY_RE = re.compile(r"^[-._a-zA-Z0-9]{1,253}$")
MAX_SECRET_BYTES = 1024 * 1024


class ConfigError(Exception):
    def __init__(self, missing: tuple[str, ...]) -> None:
        super().__init__(", ".join(missing))
        self.missing = missing


class SecretConfigError(Exception):
    pass


@dataclass(frozen=True)
class Settings:
    aws_access_key_id: str
    aws_secret_access_key: str
    aws_session_token: str | None
    aws_region: str
    node_type: str
    node_count: int
    cluster_role_arn: str | None
    node_role_arn: str | None
    values: Mapping[str, str]


def _parse_dotenv_value(raw: str) -> str:
    raw = raw.strip()
    if not raw:
        return raw
    if raw[0] not in "'\"":
        return raw
    quote = raw[0]
    if len(raw) < 2 or raw[-1] != quote:
        return raw
    inner = raw[1:-1]
    if quote == "'":
        return inner.replace("\\'", "'")
    return inner.replace('\\"', '"')


def read_dotenv(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    data: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        key = key.strip()
        if not key:
            continue
        data[key] = _parse_dotenv_value(value)
    return data


def load_settings(env: Mapping[str, str], *, app_env: Mapping[str, str] | None = None) -> Settings:
    missing = tuple(key for key in REQUIRED if not env.get(key, "").strip())
    if missing:
        raise ConfigError(missing)
    raw_count = env.get("EKS_NODE_COUNT", "").strip() or "1"
    if not raw_count.isdigit() or int(raw_count) < 1:
        raise ConfigError(("EKS_NODE_COUNT",))
    token = env.get("AWS_SESSION_TOKEN", "").strip() or None
    secret_source = app_env if app_env is not None else env
    return Settings(
        aws_access_key_id=env["AWS_ACCESS_KEY_ID"].strip(),
        aws_secret_access_key=env["AWS_SECRET_ACCESS_KEY"].strip(),
        aws_session_token=token,
        aws_region=env["AWS_REGION"].strip(),
        node_type=(env.get("EKS_NODE_TYPE", "").strip() or "t3.medium"),
        node_count=int(raw_count),
        cluster_role_arn=env.get("EKS_CLUSTER_ROLE_ARN", "").strip() or None,
        node_role_arn=env.get("EKS_NODE_ROLE_ARN", "").strip() or None,
        values={key: value for key, value in secret_source.items()},
    )


def _valid_secret_key(key: str) -> bool:
    return bool(SECRET_KEY_RE.match(key))


def _truthy(value: str) -> bool:
    return value.strip().lower() in ("1", "true", "yes", "on")


def _postgres_ssl_query(sslmode: str) -> str:
    mode = sslmode.strip()
    if not mode:
        return ""
    return f"?sslmode={quote(mode, safe='')}"


def _postgresql_url(
    user: str,
    password: str,
    host: str,
    port: str,
    database: str,
    sslmode: str,
) -> str:
    user_q = quote(user, safe="")
    password_q = quote(password, safe="")
    base = f"postgresql://{user_q}:{password_q}@{host}:{port}/{database}"
    return base + _postgres_ssl_query(sslmode)


def _jdbc_postgresql_url(host: str, port: str, database: str, sslmode: str) -> str:
    base = f"jdbc:postgresql://{host}:{port}/{database}"
    return base + _postgres_ssl_query(sslmode)


def _mongodb_url(user: str, password: str, host: str, port: str, database: str) -> str:
    user_q = quote(user, safe="")
    password_q = quote(password, safe="")
    return f"mongodb://{user_q}:{password_q}@{host}:{port}/{database}?authSource=admin"


def _redis_url(password: str, host: str, port: str, *, tls: bool, user: str = "") -> str:
    password_q = quote(password, safe="")
    scheme = "rediss" if tls else "redis"
    if user.strip():
        user_q = quote(user.strip(), safe="")
        return f"{scheme}://{user_q}:{password_q}@{host}:{port}/0"
    return f"{scheme}://:{password_q}@{host}:{port}/0"


def _secret_payload_size(data: Mapping[str, str]) -> int:
    return sum(len(k.encode("utf-8")) + len(v.encode("utf-8")) for k, v in data.items())


def application_secret_data(settings: Settings) -> dict[str, str]:
    data: dict[str, str] = {}
    for key, value in settings.values.items():
        if key in EXCLUDED_FROM_SECRET:
            continue
        if not _valid_secret_key(key):
            raise SecretConfigError(
                f"Invalid secret key '{key}' in .env. Use only letters, digits, '-', '_', and '.'."
            )
        data[key] = value

    pg_host = data["POSTGRES_HOST"].strip()
    pg_port = data["POSTGRES_PORT"].strip()
    mongo_host = data["MONGO_HOST"].strip()
    mongo_port = data["MONGO_PORT"].strip()
    redis_host = data["REDIS_HOST"].strip()
    redis_port = data["REDIS_PORT"].strip()
    sslmode = data.get("POSTGRES_SSLMODE", "")
    mongo_db = data["MONGO_DB"]
    data["API_PORT"] = "8080"
    data["SERVER_PORT"] = "8080"
    data["PORT"] = "8000"
    data["HOST"] = "0.0.0.0"
    data["DB_NAME"] = mongo_db
    data["DATABASE_A_URL"] = _postgresql_url(
        data["POSTGRES_USER"],
        data["POSTGRES_PASSWORD"],
        pg_host,
        pg_port,
        data["POSTGRES_DB_FIRST_YEAR"],
        sslmode,
    )
    data["DATABASE_B_URL"] = _postgresql_url(
        data["POSTGRES_USER"],
        data["POSTGRES_PASSWORD"],
        pg_host,
        pg_port,
        data["POSTGRES_DB_SECOND_YEAR"],
        sslmode,
    )
    data["DB_URL"] = _jdbc_postgresql_url(
        pg_host, pg_port, data["POSTGRES_DB_SECOND_YEAR"], sslmode
    )
    explicit_mongo = data.get("MONGO_URI", "").strip() or data.get("MONGO_URL", "").strip()
    if explicit_mongo:
        data["MONGO_URI"] = explicit_mongo
        data["MONGO_URL"] = explicit_mongo
    else:
        data["MONGO_URL"] = _mongodb_url(
            data["MONGO_USER"],
            data["MONGO_PASSWORD"],
            mongo_host,
            mongo_port,
            mongo_db,
        )
        data["MONGO_URI"] = data["MONGO_URL"]
    data["REDIS_URI"] = _redis_url(
        data["REDIS_PASSWORD"],
        redis_host,
        redis_port,
        tls=_truthy(data.get("REDIS_TLS", "")),
        user=data.get("REDIS_USER", ""),
    )
    data.pop("PROFILE_MS_BASE_URL", None)
    data["AUTH_MS_BASE_URL"] = "http://aether-ms-auth:8080"

    ordered = dict(sorted(data.items()))
    size = _secret_payload_size(ordered)
    if size > MAX_SECRET_BYTES:
        raise SecretConfigError(
            f"Secret aether-env exceeds the 1 MiB Kubernetes limit ({size} bytes). "
            "Remove large values from .env."
        )
    return ordered


def application_secret_fingerprint(data: Mapping[str, str]) -> str:
    digest = hashlib.sha256()
    for key, value in sorted(data.items()):
        digest.update(key.encode())
        digest.update(b"\0")
        digest.update(str(value).encode())
        digest.update(b"\0")
    return digest.hexdigest()[:12]
