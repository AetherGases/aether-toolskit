from collections.abc import Mapping
from dataclasses import dataclass
from urllib.parse import quote


REQUIRED = (
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_REGION",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "POSTGRES_DB_FIRST_YEAR",
    "POSTGRES_DB_SECOND_YEAR",
    "MONGO_USER",
    "MONGO_PASSWORD",
    "MONGO_DB",
    "REDIS_PASSWORD",
    "JWT_SECRET",
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


class ConfigError(Exception):
    def __init__(self, missing: tuple[str, ...]) -> None:
        super().__init__(", ".join(missing))
        self.missing = missing


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


def load_settings(env: Mapping[str, str]) -> Settings:
    missing = tuple(key for key in REQUIRED if not env.get(key, "").strip())
    if missing:
        raise ConfigError(missing)
    raw_count = env.get("EKS_NODE_COUNT", "").strip() or "1"
    if not raw_count.isdigit() or int(raw_count) < 1:
        raise ConfigError(("EKS_NODE_COUNT",))
    token = env.get("AWS_SESSION_TOKEN", "").strip() or None
    return Settings(
        aws_access_key_id=env["AWS_ACCESS_KEY_ID"].strip(),
        aws_secret_access_key=env["AWS_SECRET_ACCESS_KEY"].strip(),
        aws_session_token=token,
        aws_region=env["AWS_REGION"].strip(),
        node_type=(env.get("EKS_NODE_TYPE", "").strip() or "t3.medium"),
        node_count=int(raw_count),
        cluster_role_arn=env.get("EKS_CLUSTER_ROLE_ARN", "").strip() or None,
        node_role_arn=env.get("EKS_NODE_ROLE_ARN", "").strip() or None,
        values={key: value for key, value in env.items()},
    )


def application_secret_data(settings: Settings) -> dict[str, str]:
    data = {
        key: value
        for key, value in settings.values.items()
        if key not in EXCLUDED_FROM_SECRET
    }
    user = quote(data["POSTGRES_USER"], safe="")
    password = quote(data["POSTGRES_PASSWORD"], safe="")
    mongo_user = quote(data["MONGO_USER"], safe="")
    mongo_password = quote(data["MONGO_PASSWORD"], safe="")
    redis_password = quote(data["REDIS_PASSWORD"], safe="")
    mongo_db = data["MONGO_DB"]
    data["POSTGRES_HOST"] = "postgres"
    data["POSTGRES_PORT"] = "5432"
    data["MONGO_HOST"] = "mongo"
    data["MONGO_PORT"] = "27017"
    data["REDIS_HOST"] = "redis"
    data["REDIS_PORT"] = "6379"
    data["API_PORT"] = "8080"
    data["SERVER_PORT"] = "8080"
    data["PORT"] = "8000"
    data["HOST"] = "0.0.0.0"
    data["DB_NAME"] = mongo_db
    data["MONGO_URL"] = (
        f"mongodb://{mongo_user}:{mongo_password}@mongo:27017/{mongo_db}?authSource=admin"
    )
    data["MONGO_URI"] = data["MONGO_URL"]
    data["REDIS_URI"] = f"redis://:{redis_password}@redis:6379/0"
    data["DATABASE_A_URL"] = (
        f"postgresql://{user}:{password}@postgres:5432/{data['POSTGRES_DB_FIRST_YEAR']}"
    )
    data["DATABASE_B_URL"] = (
        f"postgresql://{user}:{password}@postgres:5432/{data['POSTGRES_DB_SECOND_YEAR']}"
    )
    return data
